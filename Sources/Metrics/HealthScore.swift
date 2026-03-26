import Foundation

// MARK: - Anomaly

enum Anomaly: String, CaseIterable {
    case stall
    case loop
    case hemorrhage
    case explosion
    case deepThinking = "deep_thinking"

    /// Severity order (higher = more severe).
    var severity: Int {
        switch self {
        case .explosion:    return 5
        case .hemorrhage:   return 4
        case .loop:         return 3
        case .stall:        return 2
        case .deepThinking: return 1
        }
    }
}

// MARK: - HealthResult

struct HealthResult {
    let score: Int       // 0-100
    let anomaly: Anomaly?
}

// MARK: - HealthScore

enum HealthScore {

    // MARK: - Default Weights

    static let defaultWeights: [String: Double] = [
        "tokenMin":          0.15,
        "toolFreq":          0.10,
        "idleAvgS":          0.10,
        "errorRate":         0.20,
        "thinkOutputRatio":  0.10,
        "cacheHit":          0.15,
        "subagentCount":     0.10,
        "costEUR":           0.10,
    ]

    // MARK: - Public

    static func compute(
        tokenMin: Double,
        toolFreq: Double,
        idleAvgS: Double,
        errorRate: Double,
        thinkOutputRatio: Double?,
        cacheHit: Double,
        subagentCount: Int,
        costEUR: Double,
        sessionDurationMinutes: Double,
        weights: [String: Double]? = nil
    ) -> HealthResult {

        let w = weights ?? defaultWeights

        // Individual scores (all 0.0 - 1.0)
        let sTokenMin     = scoreHigherIsBetter(value: tokenMin, healthy: 500, degraded: 100, critical: 10)
        let sToolFreq     = scoreToolFreqBellCurve(freq: toolFreq)
        let sIdleAvgS     = scoreLowerIsBetter(value: idleAvgS, healthy: 2.0, degraded: 15.0, critical: 30.0)
        let sErrorRate    = scoreLowerIsBetter(value: errorRate, healthy: 0.02, degraded: 0.10, critical: 0.30)
        let sCacheHit     = scoreHigherIsBetter(value: cacheHit, healthy: 0.60, degraded: 0.30, critical: 0.10)
        let sSubagent     = scoreLowerIsBetter(value: Double(subagentCount), healthy: 2.0, degraded: 5.0, critical: 8.0)

        // Cost rate: EUR per hour
        let sessionHours = max(sessionDurationMinutes / 60.0, 1.0 / 60.0)
        let costRate = costEUR / sessionHours
        let sCost = scoreLowerIsBetter(value: costRate, healthy: 2.0, degraded: 5.0, critical: 10.0)

        // Build weighted sum
        var totalWeight = 0.0
        var weightedSum = 0.0

        func add(_ key: String, _ score: Double) {
            let wt = w[key] ?? 0.0
            weightedSum += score * wt
            totalWeight += wt
        }

        add("tokenMin", sTokenMin)
        add("toolFreq", sToolFreq)
        add("idleAvgS", sIdleAvgS)
        add("errorRate", sErrorRate)
        add("cacheHit", sCacheHit)
        add("subagentCount", sSubagent)
        add("costEUR", sCost)

        // thinkOutputRatio: include only if available
        if let ratio = thinkOutputRatio {
            // Ideal ratio ~1-3, too high means excessive thinking
            let sThink = scoreLowerIsBetter(value: ratio, healthy: 2.0, degraded: 4.0, critical: 8.0)
            add("thinkOutputRatio", sThink)
        }
        // If nil, its weight is excluded (proportional redistribution via totalWeight)

        let rawScore: Double
        if totalWeight > 0 {
            rawScore = (weightedSum / totalWeight) * 100.0
        } else {
            rawScore = 50.0
        }

        // ── Stall duration penalty ──
        // If idle > 2min, progressively penalize health.
        // 2min idle = -10, 5min = -25, 10min = -50
        var adjustedScore = rawScore
        if idleAvgS > 120 {
            let idleMinutes = idleAvgS / 60.0
            let penalty = min(idleMinutes * 5.0, 60.0)  // cap at -60
            adjustedScore -= penalty
        }

        let clampedScore = Int(min(max(adjustedScore, 0.0), 100.0))

        // Anomaly detection (checked in order)
        let anomaly = detectAnomaly(
            tokenMin: tokenMin,
            toolFreq: toolFreq,
            idleAvgS: idleAvgS,
            errorRate: errorRate,
            thinkOutputRatio: thinkOutputRatio,
            cacheHit: cacheHit,
            subagentCount: subagentCount,
            costRate: costRate
        )

        return HealthResult(score: clampedScore, anomaly: anomaly)
    }

    // MARK: - Scoring Functions

    /// Higher value = better. Returns 1.0 at healthy, 0.0 at critical.
    static func scoreHigherIsBetter(value: Double, healthy: Double, degraded: Double, critical: Double) -> Double {
        if value >= healthy { return 1.0 }
        if value <= critical { return 0.0 }
        if value >= degraded {
            // Between degraded and healthy
            return 0.5 + 0.5 * (value - degraded) / (healthy - degraded)
        } else {
            // Between critical and degraded
            return 0.5 * (value - critical) / (degraded - critical)
        }
    }

    /// Lower value = better. Returns 1.0 at healthy, 0.0 at critical.
    static func scoreLowerIsBetter(value: Double, healthy: Double, degraded: Double, critical: Double) -> Double {
        if value <= healthy { return 1.0 }
        if value >= critical { return 0.0 }
        if value <= degraded {
            // Between healthy and degraded
            return 0.5 + 0.5 * (degraded - value) / (degraded - healthy)
        } else {
            // Between degraded and critical
            return 0.5 * (critical - value) / (critical - degraded)
        }
    }

    /// Asymmetric bell curve centered at 5 tool calls/min.
    /// Low side: freq/5. High side: 1 - (freq-5)*0.08. Clamped [0, 1].
    static func scoreToolFreqBellCurve(freq: Double) -> Double {
        if freq <= 5.0 {
            return min(max(freq / 5.0, 0.0), 1.0)
        } else {
            return min(max(1.0 - (freq - 5.0) * 0.08, 0.0), 1.0)
        }
    }

    // MARK: - Anomaly Detection

    private static func detectAnomaly(
        tokenMin: Double,
        toolFreq: Double,
        idleAvgS: Double,
        errorRate: Double,
        thinkOutputRatio: Double?,
        cacheHit: Double,
        subagentCount: Int,
        costRate: Double
    ) -> Anomaly? {

        // Check in order: deepThinking, stall, loop, hemorrhage, explosion
        if let ratio = thinkOutputRatio, ratio > 6.0, tokenMin > 200.0, errorRate < 0.05 {
            return .deepThinking
        }

        if tokenMin < 10.0, idleAvgS > 15.0 {
            return .stall
        }

        if toolFreq > 15.0, errorRate > 0.30 {
            return .loop
        }

        if costRate > 5.0, cacheHit < 0.20 {
            return .hemorrhage
        }

        if subagentCount > 8 {
            return .explosion
        }

        return nil
    }
}

// MARK: - Notification Text

extension Anomaly {
    var notificationTitle: String {
        switch self {
        case .hemorrhage:   return "Token Hemorrhage"
        case .explosion:    return "Agent Explosion"
        case .loop:         return "Error Loop"
        case .stall:        return "Session Stall"
        case .deepThinking: return "Deep Thinking"
        }
    }

    func notificationBody(project: String, snapshot: MetricsSnapshot) -> String {
        switch self {
        case .hemorrhage:
            let sessionHours = max(Date().timeIntervalSince(snapshot.startTime) / 3600, 1.0 / 60.0)
            let rate = snapshot.costEUR / sessionHours
            let cachePct = Int(snapshot.cacheHit * 100)
            return "\(project) burning €\(String(format: "%.1f", rate))/h — cache \(cachePct)%"
        case .explosion:
            return "\(project) spawned \(snapshot.subagentCount) agents"
        case .loop:
            return "\(project) looping — \(String(format: "%.0f", snapshot.toolFreq)) tool calls/min, \(Int(snapshot.errorRate * 100))% errors"
        case .stall:
            return "\(project) stalled — \(String(format: "%.0f", snapshot.idleAvgS))s avg idle"
        case .deepThinking:
            return "\(project) thinking deeply — ratio \(String(format: "%.1f", snapshot.thinkOutputRatio ?? 0))"
        }
    }
}
