import Foundation

/// Central defaults for InkPulse. All values can be overridden via ~/.inkpulse/config.json.
enum InkPulseDefaults {

    // MARK: - File Paths

    static let claudeProjectsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    static let inkpulseDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".inkpulse")
    static let heartbeatDir = inkpulseDir.appendingPathComponent("heartbeats")
    static let reportsDir = inkpulseDir.appendingPathComponent("reports")
    static let offsetsFile = inkpulseDir.appendingPathComponent("offsets.json")
    static let configFile = inkpulseDir.appendingPathComponent("config.json")

    // MARK: - Timing

    static let refreshIntervalMs: Int = 1_000
    static let heartbeatIntervalMs: Int = 5_000
    static let purgeDays: Int = 30
    static let sessionTimeoutSeconds: Int = 300

    // MARK: - Window Sizes

    static let shortWindowSeconds: Int = 60
    static let longWindowSeconds: Int = 300

    // MARK: - Context Limits

    static let defaultContextLimits: [String: Int] = [
        "claude-opus-4": 200_000,
        "claude-opus-4-6[1m]": 1_000_000,
        "claude-sonnet-4": 200_000,
        "claude-sonnet-4-6": 200_000,
        "claude-haiku-4-5": 200_000,
        "claude-haiku-3.5": 200_000,
    ]

    static let fallbackContextLimit: Int = 200_000

    // MARK: - Budget

    static let defaultDailyBudgetEUR: Double = 0  // 0 = disabled
    static let defaultBudgetAlertThresholds: [Double] = [0.8, 1.0]

    // MARK: - Default Metric Weights

    static let defaultWeights: [String: Double] = [
        "costEUR":           0.10,
        "tokenMin":          0.15,
        "cacheHit":          0.15,
        "errorRate":         0.20,
        "thinkOutputRatio":  0.10,
        "toolFreq":          0.10,
        "subagentCount":     0.10,
        "idleAvgS":          0.10,
    ]
}
