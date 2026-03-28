import Foundation

/// Tracks per-session metrics state, ingesting events and producing snapshots.
final class SessionMetrics {

    let sessionId: String
    private(set) var model: String = "unknown"
    let startTime: Date
    private(set) var lastEventTime: Date

    // MARK: - Internal Accumulators

    /// Timestamped output token counts for windowed tok/min.
    private var outputTokenEvents: [(date: Date, tokens: Int)] = []

    /// Timestamped tool-use flags for windowed toolFreq.
    private var toolEvents: [(date: Date, isError: Bool)] = []

    /// Gaps > 1 s between consecutive events (timestamped by the later event).
    private var idleGaps: [(date: Date, gap: Double)] = []

    /// Timestamped tool names for diversity/domain tracking (EGI).
    private var toolNameEvents: [(date: Date, name: String)] = []

    /// Cumulative tool invocation counts by name.
    private var toolCountsByName: [String: Int] = [:]

    /// EGI state tracker.
    private(set) var egiTracker = EGITracker()

    /// Subagent tracking via Agent tool uses (not queue-operations).
    /// queue-operations are user messages queued while Claude is busy, NOT subagents.
    private var agentToolSpawnCount: Int = 0

    /// Cumulative cache counters.
    private var totalInput: Int = 0
    private var totalCacheRead: Int = 0
    private var totalCacheCreation: Int = 0

    /// Cumulative cost.
    private(set) var costEUR: Double = 0.0

    /// Thinking / output token estimates for ratio.
    private var estimatedThinkingTokens: Int = 0
    private var estimatedOutputTokens: Int = 0
    private var hasThinkingData: Bool = false

    /// Previous event timestamp for idle-gap detection.
    private var previousTimestamp: Date?

    // MARK: - Context Window (Feature 1)

    /// Total context tokens from the last assistant event usage.
    private(set) var lastContextTokens: Int = 0

    // MARK: - Last Tool + Task Name (Feature 2)

    /// Name of the last tool invoked (e.g. "Edit", "Bash", "Read").
    private(set) var lastToolName: String?
    /// First argument of the last tool (e.g. file_path, command). Truncated to 30 chars.
    private(set) var lastToolTarget: String?
    /// Active task name from TaskCreate/TaskUpdate progress events.
    private(set) var activeTaskName: String?

    // MARK: - Project Inference (from tool file paths)

    /// Ring buffer of recent full file paths from tool_use events (max 30).
    private var recentToolPaths: [String] = []
    private static let maxToolPaths = 30

    // MARK: - Init

    init(sessionId: String, startTime: Date) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.lastEventTime = startTime
    }

    // MARK: - Ingest

    func ingest(_ event: ClaudeEvent) {
        guard let ts = event.timestamp else { return }
        lastEventTime = ts

        // Idle gap detection (all event types)
        if let prev = previousTimestamp {
            let delta = ts.timeIntervalSince(prev)
            if delta > 1.0 {
                idleGaps.append((date: ts, gap: delta))
            }
        }
        previousTimestamp = ts

        switch event {
        case .assistant(let msg, let timestamp, _):
            model = msg.model

            // Output tokens for tok/min window
            outputTokenEvents.append((date: timestamp, tokens: msg.usage.outputTokens))

            // Context window tokens (Feature 1)
            lastContextTokens = msg.usage.inputTokens
                + msg.usage.cacheReadInputTokens
                + msg.usage.cacheCreationInputTokens

            // Last tool name + target from tool_use content blocks (Feature 2)
            for tool in msg.toolUses {
                toolCountsByName[tool.name, default: 0] += 1
            }
            if let lastTool = msg.toolUses.last {
                lastToolName = lastTool.name
                lastToolTarget = lastTool.target
            }

            // Collect full paths for project inference
            for tool in msg.toolUses {
                if let fp = tool.fullPath {
                    recentToolPaths.append(fp)
                    if recentToolPaths.count > Self.maxToolPaths {
                        recentToolPaths.removeFirst()
                    }
                }
            }

            // Task name tracking + subagent counting
            for tool in msg.toolUses {
                if (tool.name == "TaskCreate" || tool.name == "TaskUpdate"),
                   let subject = tool.subject {
                    activeTaskName = subject
                }
                if tool.name == "Agent" {
                    agentToolSpawnCount += 1
                }
            }

            // Thinking / output estimation
            if let thinkText = msg.thinkingText, !thinkText.isEmpty {
                // Rough estimate: 4 chars per token
                estimatedThinkingTokens += max(thinkText.count / 4, 1)
                hasThinkingData = true
            }
            if let outText = msg.outputText, !outText.isEmpty {
                estimatedOutputTokens += max(outText.count / 4, 1)
            }
            // Also add usage-reported output tokens to estimate
            estimatedOutputTokens += msg.usage.outputTokens

            // Cache totals
            totalInput += msg.usage.inputTokens
            totalCacheRead += msg.usage.cacheReadInputTokens
            totalCacheCreation += msg.usage.cacheCreationInputTokens

            // Cost (with tiered pricing for Sonnet >200K)
            if let c = Pricing.costEUR(
                model: msg.model,
                inputTokens: msg.usage.inputTokens,
                outputTokens: msg.usage.outputTokens,
                cacheReadTokens: msg.usage.cacheReadInputTokens,
                cacheCreationTokens: msg.usage.cacheCreationInputTokens,
                contextTokens: lastContextTokens
            ) {
                costEUR += c
            }

        case .progress(_, let toolName, let isToolUse, let isError, let timestamp, _):
            if isToolUse {
                toolEvents.append((date: timestamp, isError: isError))
                if let name = toolName {
                    toolNameEvents.append((date: timestamp, name: name))
                    toolCountsByName[name, default: 0] += 1
                    lastToolName = name
                }
            }

        case .queueOperation:
            // queue-operations are user messages queued while Claude is busy.
            // They are NOT subagent spawns — ignore for subagent tracking.
            break

        case .user(let errorCount, let timestamp, _):
            // Tool result errors from user events
            if errorCount > 0 {
                for _ in 0..<errorCount {
                    toolEvents.append((date: timestamp, isError: true))
                }
            }

        case .system, .unknown:
            break
        }
    }

    // MARK: - Project Inference

    /// Infers project name from the most frequent directory in collected tool paths.
    /// Returns nil if no meaningful project can be determined.
    var inferredProject: String? {
        guard !recentToolPaths.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Directories that are structural containers, not project names
        let containers: Set<String> = [
            "Downloads", "projects", "Documents", "Desktop",
            "Library", ".claude", "Applications", "tmp",
            "clients", "src", "public", "assets"
        ]

        var candidates: [String: Int] = [:]

        for path in recentToolPaths {
            // Strip home prefix
            var relative = path
            if relative.hasPrefix(home) {
                relative = String(relative.dropFirst(home.count))
                if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            }

            // Walk components, skip containers, take first meaningful one
            let components = relative.components(separatedBy: "/")
            var found: String? = nil
            for component in components {
                if component.isEmpty || component.hasPrefix(".") { continue }
                if containers.contains(component) { continue }
                found = component
                break
            }

            if let project = found {
                candidates[project, default: 0] += 1
            }
        }

        // Winner = most frequent
        guard let winner = candidates.max(by: { $0.value < $1.value })?.key else { return nil }
        return Self.smartCapitalize(winner)
    }

    /// Smart capitalize: "luxguard" → "Luxguard", "my-project" → "My Project".
    /// Leaves already-capitalized names unchanged.
    static func smartCapitalize(_ name: String) -> String {
        if name.isEmpty { return name }
        if name.first?.isUppercase == true { return name }
        if name.contains("-") {
            return name.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        if name.contains("_") {
            return name.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: - Snapshot

    func snapshot(at now: Date) -> MetricsSnapshot {
        let shortWindow = Double(InkPulseDefaults.shortWindowSeconds)  // 60s
        let longWindow = Double(InkPulseDefaults.longWindowSeconds)    // 300s

        let shortCutoff = now.addingTimeInterval(-shortWindow)
        let longCutoff = now.addingTimeInterval(-longWindow)

        // 1. tokenMin: output tokens in 60s window / window minutes
        let recentTokens = outputTokenEvents
            .filter { $0.date > shortCutoff }
            .reduce(0) { $0 + $1.tokens }
        let windowMinutes = shortWindow / 60.0
        let tokenMin = Double(recentTokens) / windowMinutes

        // 2. toolFreq: tool events in 60s / window minutes
        let recentTools = toolEvents.filter { $0.date > shortCutoff }
        let toolFreq = Double(recentTools.count) / windowMinutes

        // 3. idleAvgS: mean of idle gaps >1s in 60s window
        let recentGaps = idleGaps.filter { $0.date > shortCutoff }
        let idleAvgS: Double
        if recentGaps.isEmpty {
            idleAvgS = 0.0
        } else {
            idleAvgS = recentGaps.map(\.gap).reduce(0, +) / Double(recentGaps.count)
        }

        // 4. errorRate: errors / total tools in 5min window
        let longTools = toolEvents.filter { $0.date > longCutoff }
        let longErrors = longTools.filter { $0.isError }.count
        let errorRate: Double
        if longTools.isEmpty {
            errorRate = 0.0
        } else {
            errorRate = Double(longErrors) / Double(longTools.count)
        }

        // 5. thinkOutputRatio
        let thinkOutputRatio: Double?
        if hasThinkingData && estimatedOutputTokens > 0 {
            thinkOutputRatio = Double(estimatedThinkingTokens) / Double(estimatedOutputTokens)
        } else {
            thinkOutputRatio = nil
        }

        // 6. cacheHit
        let cacheDenom = totalInput + totalCacheRead + totalCacheCreation
        let cacheHit: Double
        if cacheDenom == 0 {
            cacheHit = 0.0
        } else {
            cacheHit = Double(totalCacheRead) / Double(cacheDenom)
        }

        // 7. subagentCount (from Agent tool uses, not queue-operations)
        let subagentCount = agentToolSpawnCount

        // 8. costEUR already tracked cumulatively

        // Session duration
        let sessionDurationMinutes = now.timeIntervalSince(startTime) / 60.0

        // Health score
        let healthResult = HealthScore.compute(
            tokenMin: tokenMin,
            toolFreq: toolFreq,
            idleAvgS: idleAvgS,
            errorRate: errorRate,
            thinkOutputRatio: thinkOutputRatio,
            cacheHit: cacheHit,
            subagentCount: subagentCount,
            costEUR: costEUR,
            sessionDurationMinutes: sessionDurationMinutes
        )

        // 9. Tool diversity & domain spread (EGI signals)
        let recentToolNames = toolNameEvents.filter { $0.date > shortCutoff }
        let toolDiversity = Set(recentToolNames.map(\.name)).count

        let egiDomainCutoff = now.addingTimeInterval(-120) // 2min window for domains
        let domainToolNames = toolNameEvents.filter { $0.date > egiDomainCutoff }
        let domainSpread = Set(domainToolNames.map { EGIDomain.classify($0.name) }).count

        // 10. EGI state machine evaluation
        let egiResult = egiTracker.evaluate(
            tokenMin: tokenMin,
            errorRate: errorRate,
            cacheHit: cacheHit,
            toolDiversity: toolDiversity,
            domainSpread: domainSpread,
            idleAvgS: idleAvgS,
            thinkOutputRatio: thinkOutputRatio,
            subagentCount: subagentCount,
            at: now
        )

        // Prune old events outside long window
        outputTokenEvents.removeAll { $0.date <= longCutoff }
        toolEvents.removeAll { $0.date <= longCutoff }
        idleGaps.removeAll { $0.date <= longCutoff }
        toolNameEvents.removeAll { $0.date <= longCutoff }

        // Context window % (Feature 1)
        let config = ConfigLoader.load()
        let contextLimit = ConfigLoader.contextLimit(for: model, config: config)
        let contextPercent: Double
        if contextLimit > 0 && lastContextTokens > 0 {
            contextPercent = Double(lastContextTokens) / Double(contextLimit)
        } else {
            contextPercent = 0.0
        }

        return MetricsSnapshot(
            sessionId: sessionId,
            model: model,
            tokenMin: tokenMin,
            toolFreq: toolFreq,
            idleAvgS: idleAvgS,
            errorRate: errorRate,
            thinkOutputRatio: thinkOutputRatio,
            cacheHit: cacheHit,
            subagentCount: subagentCount,
            costEUR: costEUR,
            health: healthResult.score,
            anomaly: healthResult.anomaly?.rawValue,
            startTime: startTime,
            lastEventTime: lastEventTime,
            egiState: egiResult.state,
            egiConfidence: egiResult.confidence,
            toolDiversity: toolDiversity,
            domainSpread: domainSpread,
            lastContextTokens: lastContextTokens,
            contextPercent: contextPercent,
            lastToolName: lastToolName,
            lastToolTarget: lastToolTarget,
            activeTaskName: activeTaskName,
            inferredProject: inferredProject,
            toolCounts: toolCountsByName
        )
    }
}
