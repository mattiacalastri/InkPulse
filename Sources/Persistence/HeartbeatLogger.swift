import Foundation

// MARK: - HeartbeatRecord

struct HeartbeatRecord: Codable {
    let ts: String
    let sessionId: String
    let project: String?
    let health: Int
    let tokenMin: Double
    let toolFreq: Double
    let idleAvgS: Double
    let errorRate: Double
    let thinkOutputRatio: Double?
    let cacheHit: Double
    let subagentCount: Int
    let costEur: Double
    let model: String
    let anomaly: String?

    enum CodingKeys: String, CodingKey {
        case ts
        case sessionId = "session_id"
        case project
        case health
        case tokenMin = "token_min"
        case toolFreq = "tool_freq"
        case idleAvgS = "idle_avg_s"
        case errorRate = "error_rate"
        case thinkOutputRatio = "think_output_ratio"
        case cacheHit = "cache_hit"
        case subagentCount = "subagent_count"
        case costEur = "cost_eur"
        case model
        case anomaly
    }

    init(from snap: MetricsSnapshot) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        self.ts = formatter.string(from: snap.lastEventTime)
        self.sessionId = snap.sessionId
        self.project = nil
        self.health = snap.health
        self.tokenMin = snap.tokenMin
        self.toolFreq = snap.toolFreq
        self.idleAvgS = snap.idleAvgS
        self.errorRate = snap.errorRate
        self.thinkOutputRatio = snap.thinkOutputRatio
        self.cacheHit = snap.cacheHit
        self.subagentCount = snap.subagentCount
        self.costEur = snap.costEUR
        self.model = snap.model
        self.anomaly = snap.anomaly
    }
}

// MARK: - HeartbeatLogger

final class HeartbeatLogger {

    private let heartbeatDir: URL
    private let reportsDir: URL
    private let purgeDays: Int
    private let encoder = JSONEncoder()

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    init(
        heartbeatDir: URL = InkPulseDefaults.heartbeatDir,
        purgeDays: Int = InkPulseDefaults.purgeDays
    ) {
        self.heartbeatDir = heartbeatDir
        self.reportsDir = InkPulseDefaults.reportsDir
        self.purgeDays = purgeDays
        ensureDirectories()
    }

    // MARK: - Log

    func logSnapshots(_ snapshots: [MetricsSnapshot]) {
        guard !snapshots.isEmpty else { return }

        let dateStr = Self.fileDateFormatter.string(from: Date())
        let fileURL = heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")

        var lines = Data()
        for snap in snapshots {
            let record = HeartbeatRecord(from: snap)
            guard let jsonData = try? encoder.encode(record) else { continue }
            lines.append(jsonData)
            lines.append(Data("\n".utf8))
        }

        guard !lines.isEmpty else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Append mode
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(lines)
        } else {
            try? lines.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Purge

    func purgeOldFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: heartbeatDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -purgeDays, to: Date()) ?? Date()

        for file in files {
            guard file.lastPathComponent.hasPrefix("heartbeat-"),
                  file.pathExtension == "jsonl" else { continue }

            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: - Directory Setup

    func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: heartbeatDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: reportsDir, withIntermediateDirectories: true)
    }
}
