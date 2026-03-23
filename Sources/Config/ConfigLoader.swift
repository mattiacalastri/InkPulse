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

    enum CodingKeys: String, CodingKey {
        case refreshIntervalMs = "refresh_interval_ms"
        case heartbeatIntervalMs = "heartbeat_interval_ms"
        case purgeDays = "purge_days"
        case sessionTimeoutSeconds = "session_timeout_seconds"
        case shortWindowSeconds = "short_window_seconds"
        case longWindowSeconds = "long_window_seconds"
        case weights
    }

    /// Defaults matching `InkPulseDefaults`.
    static let `default` = InkPulseConfig(
        refreshIntervalMs: InkPulseDefaults.refreshIntervalMs,
        heartbeatIntervalMs: InkPulseDefaults.heartbeatIntervalMs,
        purgeDays: InkPulseDefaults.purgeDays,
        sessionTimeoutSeconds: InkPulseDefaults.sessionTimeoutSeconds,
        shortWindowSeconds: InkPulseDefaults.shortWindowSeconds,
        longWindowSeconds: InkPulseDefaults.longWindowSeconds,
        weights: InkPulseDefaults.defaultWeights
    )
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
}
