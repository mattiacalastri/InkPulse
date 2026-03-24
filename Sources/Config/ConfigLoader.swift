import Foundation

/// User-overridable configuration loaded from ~/.inkpulse/config.json.
struct InkPulseConfig: Codable {
    var refreshIntervalMs: Int
    var heartbeatIntervalMs: Int
    var purgeDays: Int
    var sessionTimeoutSeconds: Int
    var shortWindowSeconds: Int
    var longWindowSeconds: Int
    var weights: [String: Double]
    var contextLimits: [String: Int]
    var dailyBudgetEUR: Double
    var budgetAlertThresholds: [Double]
    var soundOnAnomaly: Bool

    enum CodingKeys: String, CodingKey {
        case refreshIntervalMs = "refresh_interval_ms"
        case heartbeatIntervalMs = "heartbeat_interval_ms"
        case purgeDays = "purge_days"
        case sessionTimeoutSeconds = "session_timeout_seconds"
        case shortWindowSeconds = "short_window_seconds"
        case longWindowSeconds = "long_window_seconds"
        case weights
        case contextLimits = "context_limits"
        case dailyBudgetEUR = "daily_budget_eur"
        case budgetAlertThresholds = "budget_alert_thresholds"
        case soundOnAnomaly = "sound_on_anomaly"
    }

    /// Defaults matching `InkPulseDefaults`.
    static let `default` = InkPulseConfig(
        refreshIntervalMs: InkPulseDefaults.refreshIntervalMs,
        heartbeatIntervalMs: InkPulseDefaults.heartbeatIntervalMs,
        purgeDays: InkPulseDefaults.purgeDays,
        sessionTimeoutSeconds: InkPulseDefaults.sessionTimeoutSeconds,
        shortWindowSeconds: InkPulseDefaults.shortWindowSeconds,
        longWindowSeconds: InkPulseDefaults.longWindowSeconds,
        weights: InkPulseDefaults.defaultWeights,
        contextLimits: InkPulseDefaults.defaultContextLimits,
        dailyBudgetEUR: InkPulseDefaults.defaultDailyBudgetEUR,
        budgetAlertThresholds: InkPulseDefaults.defaultBudgetAlertThresholds,
        soundOnAnomaly: true
    )

    init(
        refreshIntervalMs: Int,
        heartbeatIntervalMs: Int,
        purgeDays: Int,
        sessionTimeoutSeconds: Int,
        shortWindowSeconds: Int,
        longWindowSeconds: Int,
        weights: [String: Double],
        contextLimits: [String: Int],
        dailyBudgetEUR: Double,
        budgetAlertThresholds: [Double],
        soundOnAnomaly: Bool
    ) {
        self.refreshIntervalMs = refreshIntervalMs
        self.heartbeatIntervalMs = heartbeatIntervalMs
        self.purgeDays = purgeDays
        self.sessionTimeoutSeconds = sessionTimeoutSeconds
        self.shortWindowSeconds = shortWindowSeconds
        self.longWindowSeconds = longWindowSeconds
        self.weights = weights
        self.contextLimits = contextLimits
        self.dailyBudgetEUR = dailyBudgetEUR
        self.budgetAlertThresholds = budgetAlertThresholds
        self.soundOnAnomaly = soundOnAnomaly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMs = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMs) ?? InkPulseDefaults.refreshIntervalMs
        heartbeatIntervalMs = try container.decodeIfPresent(Int.self, forKey: .heartbeatIntervalMs) ?? InkPulseDefaults.heartbeatIntervalMs
        purgeDays = try container.decodeIfPresent(Int.self, forKey: .purgeDays) ?? InkPulseDefaults.purgeDays
        sessionTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .sessionTimeoutSeconds) ?? InkPulseDefaults.sessionTimeoutSeconds
        shortWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .shortWindowSeconds) ?? InkPulseDefaults.shortWindowSeconds
        longWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .longWindowSeconds) ?? InkPulseDefaults.longWindowSeconds
        weights = try container.decodeIfPresent([String: Double].self, forKey: .weights) ?? InkPulseDefaults.defaultWeights
        contextLimits = try container.decodeIfPresent([String: Int].self, forKey: .contextLimits) ?? InkPulseDefaults.defaultContextLimits
        dailyBudgetEUR = try container.decodeIfPresent(Double.self, forKey: .dailyBudgetEUR) ?? InkPulseDefaults.defaultDailyBudgetEUR
        budgetAlertThresholds = try container.decodeIfPresent([Double].self, forKey: .budgetAlertThresholds) ?? InkPulseDefaults.defaultBudgetAlertThresholds
        soundOnAnomaly = try container.decodeIfPresent(Bool.self, forKey: .soundOnAnomaly) ?? true
    }
}

/// Reads ~/.inkpulse/config.json and falls back to defaults on any error.
enum ConfigLoader {

    static func load() -> InkPulseConfig {
        let url = InkPulseDefaults.configFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(InkPulseConfig.self, from: data)
        } catch {
            print("[InkPulse] Failed to load config: \(error.localizedDescription). Using defaults.")
            return .default
        }
    }

    /// Resolves the context limit for a given model string.
    static func contextLimit(for model: String, config: InkPulseConfig) -> Int {
        // Check if the model string contains any key from the limits map
        for (key, limit) in config.contextLimits {
            if model.contains(key) {
                return limit
            }
        }
        return InkPulseDefaults.fallbackContextLimit
    }
}
