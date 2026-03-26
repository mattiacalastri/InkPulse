import Foundation

struct PillarOverride: Codable {
    let name: String
    let color: String
    let short: String
}

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
    var pillarOverrides: [String: PillarOverride]

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
        case pillarOverrides = "pillar_overrides"
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
        soundOnAnomaly: true,
        pillarOverrides: [:]
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
        soundOnAnomaly: Bool,
        pillarOverrides: [String: PillarOverride] = [:]
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
        self.pillarOverrides = pillarOverrides
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
        pillarOverrides = try container.decodeIfPresent([String: PillarOverride].self, forKey: .pillarOverrides) ?? [:]
    }
}

/// Reads ~/.inkpulse/config.json and falls back to defaults on any error.
/// Caches the result and only re-reads from disk when the file's modification date changes.
enum ConfigLoader {

    private static var cachedConfig: InkPulseConfig?
    private static var cachedModDate: Date?

    static func load() -> InkPulseConfig {
        let url = InkPulseDefaults.configFile
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .default
        }

        // Check file modification date — return cache if unchanged
        let modDate: Date? = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let modDate, let cachedMod = cachedModDate, let cached = cachedConfig, modDate == cachedMod {
            return cached
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let config = try decoder.decode(InkPulseConfig.self, from: data)
            cachedConfig = config
            cachedModDate = modDate
            return config
        } catch {
            print("[InkPulse] Failed to load config: \(error.localizedDescription). Using defaults.")
            return .default
        }
    }

    /// Resolves the context limit for a given model string.
    /// Sorts keys by length descending so longer (more specific) matches win.
    static func contextLimit(for model: String, config: InkPulseConfig) -> Int {
        let sortedKeys = config.contextLimits.keys.sorted { $0.count > $1.count }
        for key in sortedKeys {
            if model.contains(key) {
                return config.contextLimits[key] ?? InkPulseDefaults.fallbackContextLimit
            }
        }
        return InkPulseDefaults.fallbackContextLimit
    }
}
