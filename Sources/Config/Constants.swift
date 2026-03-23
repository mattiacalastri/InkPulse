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

    // MARK: - Health Thresholds

    /// Each threshold is (green, yellow) — anything above yellow is red.
    enum HealthThreshold {
        static let costPerMinuteEUR: (green: Double, yellow: Double) = (0.10, 0.30)
        static let tokensPerSecond: (green: Double, yellow: Double) = (50.0, 200.0)
        static let cacheHitRate: (green: Double, yellow: Double) = (0.60, 0.30)
        static let errorRate: (green: Double, yellow: Double) = (0.02, 0.10)
        static let sessionDurationMinutes: (green: Double, yellow: Double) = (30.0, 90.0)
        static let toolCallRate: (green: Double, yellow: Double) = (5.0, 15.0)
        static let modelMixOpusPercent: (green: Double, yellow: Double) = (0.30, 0.60)
        static let idlePercent: (green: Double, yellow: Double) = (0.20, 0.50)
    }

    // MARK: - Default Metric Weights

    static let defaultWeights: [String: Double] = [
        "cost_per_minute": 0.20,
        "tokens_per_second": 0.10,
        "cache_hit_rate": 0.15,
        "error_rate": 0.15,
        "session_duration": 0.10,
        "tool_call_rate": 0.10,
        "model_mix_opus_percent": 0.10,
        "idle_percent": 0.10,
    ]
}
