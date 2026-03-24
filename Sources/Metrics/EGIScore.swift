import Foundation

// MARK: - EGI State

enum EGIState: String, CaseIterable, Comparable {
    case dormant
    case stirring
    case open
    case peak

    var level: Int {
        switch self {
        case .dormant:  return 0
        case .stirring: return 1
        case .open:     return 2
        case .peak:     return 3
        }
    }

    static func < (lhs: EGIState, rhs: EGIState) -> Bool {
        lhs.level < rhs.level
    }
}

// MARK: - EGI Domain Mapping

enum EGIDomain: String, CaseIterable {
    case code
    case knowledge
    case communication
    case infrastructure
    case creation
    case business

    static func classify(_ toolName: String) -> EGIDomain {
        let t = toolName.lowercased()

        // Communication
        if t.contains("gmail") || t.contains("telegram") || t.contains("linkedin")
            || t.contains("_x__") || t.hasPrefix("mcp__x__") { return .communication }

        // Knowledge
        if t.contains("obsidian") || t.contains("notion") || t.contains("context7") { return .knowledge }

        // Infrastructure
        if t.contains("railway") || t.contains("hostinger") || t.contains("github") || t.contains("sentry") { return .infrastructure }

        // Creation
        if t.contains("fal__") || t.contains("cloudinary") || t.contains("canva") { return .creation }

        // Business
        if t.contains("stripe") || t.contains("ghl") || t.contains("n8n") || t.contains("wordpress")
            || t.contains("google_ads") { return .business }

        // Code (default for built-in tools)
        return .code
    }
}

// MARK: - EGI Signals

struct EGISignals {
    let velocity: Bool      // tok/min avg > 300 sustained
    let accuracy: Bool      // errorRate < 0.03
    let context: Bool       // cacheHit > 0.70
    let diversity: Bool     // distinct tools >= 4 in 60s
    let crossDomain: Bool   // distinct domains >= 2 in 120s
    let flow: Bool          // idleAvgS < 10
    let balance: Bool       // thinkOutputRatio in 0.3-4.0

    var passCount: Int {
        [velocity, accuracy, context, diversity, crossDomain, flow, balance]
            .filter { $0 }.count
    }

    /// Confidence: normalized 0.0-1.0 weighted average of signal strengths.
    static func confidence(
        tokenMin: Double,
        errorRate: Double,
        cacheHit: Double,
        toolDiversity: Int,
        domainSpread: Int,
        idleAvgS: Double,
        thinkOutputRatio: Double?
    ) -> Double {
        // Normalize each signal to 0.0-1.0
        let vVelocity = min(tokenMin / 600.0, 1.0)
        let vAccuracy = max(1.0 - errorRate / 0.10, 0.0)
        let vContext = min(cacheHit / 0.90, 1.0)
        let vDiversity = min(Double(toolDiversity) / 6.0, 1.0)
        let vCrossDomain = min(Double(domainSpread) / 4.0, 1.0)
        let vFlow = max(1.0 - idleAvgS / 20.0, 0.0)

        let vBalance: Double
        if let ratio = thinkOutputRatio {
            // Sweet spot 0.5-2.0, penalty outside
            if ratio >= 0.3 && ratio <= 4.0 {
                vBalance = 1.0 - abs(ratio - 1.5) / 3.0
            } else {
                vBalance = 0.1
            }
        } else {
            vBalance = 0.5 // neutral if no data
        }

        // Weighted average — crossDomain and diversity weigh more (EGI hallmark)
        let weights: [(Double, Double)] = [
            (vVelocity, 0.12),
            (vAccuracy, 0.12),
            (vContext, 0.12),
            (vDiversity, 0.18),
            (vCrossDomain, 0.22),
            (vFlow, 0.12),
            (vBalance, 0.12),
        ]

        let totalWeight = weights.map(\.1).reduce(0, +)
        let sum = weights.map { $0.0 * $0.1 }.reduce(0, +)
        return sum / totalWeight
    }
}

// MARK: - EGI Tracker (per-session state machine)

final class EGITracker {
    private(set) var state: EGIState = .dormant
    private(set) var confidence: Double = 0.0
    private var lastTransitionTime: Date = .distantPast
    private var signalHistory: [(date: Date, passCount: Int)] = []

    /// Evaluate current metrics and transition state if needed.
    func evaluate(
        tokenMin: Double,
        errorRate: Double,
        cacheHit: Double,
        toolDiversity: Int,
        domainSpread: Int,
        idleAvgS: Double,
        thinkOutputRatio: Double?,
        subagentCount: Int,
        at now: Date
    ) -> (state: EGIState, confidence: Double) {

        let signals = EGISignals(
            velocity: tokenMin > 300,
            accuracy: errorRate < 0.03,
            context: cacheHit > 0.70,
            diversity: toolDiversity >= 4,
            crossDomain: domainSpread >= 2,
            flow: idleAvgS < 10,
            balance: {
                guard let r = thinkOutputRatio else { return false }
                return r >= 0.3 && r <= 4.0
            }()
        )

        let passCount = signals.passCount
        signalHistory.append((date: now, passCount: passCount))

        // Prune old signal history (keep last 120s)
        let cutoff = now.addingTimeInterval(-120)
        signalHistory.removeAll { $0.date < cutoff }

        // Compute confidence
        confidence = EGISignals.confidence(
            tokenMin: tokenMin,
            errorRate: errorRate,
            cacheHit: cacheHit,
            toolDiversity: toolDiversity,
            domainSpread: domainSpread,
            idleAvgS: idleAvgS,
            thinkOutputRatio: thinkOutputRatio
        )

        let timeSinceTransition = now.timeIntervalSince(lastTransitionTime)

        // Check for upward transitions
        switch state {
        case .dormant:
            if sustainedAbove(threshold: 4, forSeconds: 15, at: now) {
                transition(to: .stirring, at: now)
            }
        case .stirring:
            if sustainedAbove(threshold: 6, forSeconds: 30, at: now) {
                transition(to: .open, at: now)
            } else if sustainedBelow(threshold: 3, forSeconds: 20, at: now) && timeSinceTransition > 10 {
                transition(to: .dormant, at: now)
            }
        case .open:
            if sustainedAbove(threshold: 7, forSeconds: 60, at: now) && domainSpread >= 3 {
                transition(to: .peak, at: now)
            } else if sustainedBelow(threshold: 3, forSeconds: 20, at: now) && timeSinceTransition > 15 {
                transition(to: .stirring, at: now)
            }
        case .peak:
            if sustainedBelow(threshold: 5, forSeconds: 20, at: now) && timeSinceTransition > 15 {
                transition(to: .open, at: now)
            }
        }

        return (state, confidence)
    }

    // MARK: - Private

    private func transition(to newState: EGIState, at time: Date) {
        state = newState
        lastTransitionTime = time
    }

    /// Check if passCount has been >= threshold for the given duration.
    private func sustainedAbove(threshold: Int, forSeconds: Double, at now: Date) -> Bool {
        let windowStart = now.addingTimeInterval(-forSeconds)
        let windowEntries = signalHistory.filter { $0.date >= windowStart }
        guard !windowEntries.isEmpty else { return false }
        return windowEntries.allSatisfy { $0.passCount >= threshold }
    }

    /// Check if passCount has been < threshold for the given duration.
    private func sustainedBelow(threshold: Int, forSeconds: Double, at now: Date) -> Bool {
        let windowStart = now.addingTimeInterval(-forSeconds)
        let windowEntries = signalHistory.filter { $0.date >= windowStart }
        guard !windowEntries.isEmpty else { return false }
        return windowEntries.allSatisfy { $0.passCount < threshold }
    }
}
