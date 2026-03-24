import SwiftUI
import AppKit

final class AppState: ObservableObject {

    @Published var metricsEngine = MetricsEngine()
    @Published var tokenHistory: [Double] = []
    @Published var isPaused = false
    @Published var historyStore = HistoryStore()
        @Published var sessionFilePaths: [String: String] = [:] // sessionId → filePath
    @Published var sessionCwds: [String: String] = [:] // sessionId → cwd

    private var heartbeatLogger: HeartbeatLogger?
    private var sessionWatcher: SessionWatcher?
    private var refreshTimer: Timer?
    private var heartbeatTimer: Timer?
    private(set) var notificationManager = NotificationManager()
    private(set) var anomalyWatcher: AnomalyWatcher?

    private let maxTokenHistory = 300  // ~5 min at 1 sample/s

    // MARK: - Start

    func start() {
        let config = ConfigLoader.load()

        heartbeatLogger = HeartbeatLogger(purgeDays: config.purgeDays)

        let projectsDir = InkPulseDefaults.claudeProjectsPath

        sessionWatcher = SessionWatcher(projectsDir: projectsDir) { [weak self] events in
            guard let self = self, !self.isPaused else { return }
            AppState.log("Received \(events.count) events")
            for event in events {
                self.metricsEngine.ingest(event)
            }
        }

        // Restore offsets
        let offsets = OffsetCheckpoint.load()
        sessionWatcher?.restoreOffsets(offsets)

        sessionWatcher?.start()
        historyStore.start()
        Self.log("Started. Watching: \(projectsDir.path)")

        // 1s refresh timer
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(config.refreshIntervalMs) / 1000.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // 5s heartbeat timer
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Double(config.heartbeatIntervalMs) / 1000.0, repeats: true) { [weak self] _ in
            self?.heartbeat()
        }

        // Purge old files on launch
        heartbeatLogger?.purgeOldFiles()

        // Notifications
        notificationManager.requestAuthorization()
        anomalyWatcher = AnomalyWatcher(notificationManager: notificationManager)
    }

    // MARK: - Refresh

    private func refresh() {
        guard !isPaused else { return }
        metricsEngine.refreshSnapshots()

        // Append average tokenMin to history for sparkline
        let snaps = Array(metricsEngine.sessions.values)
        if !snaps.isEmpty {
            let avgTokenMin = snaps.map(\.tokenMin).reduce(0, +) / Double(snaps.count)
            AppState.log("\(snaps.count) sessions, health=\(metricsEngine.aggregateHealth), tok/min=\(Int(avgTokenMin))")
            tokenHistory.append(avgTokenMin)
            if tokenHistory.count > maxTokenHistory {
                tokenHistory.removeFirst(tokenHistory.count - maxTokenHistory)
            }
        }

        // Anomaly check
        anomalyWatcher?.check(sessions: metricsEngine.sessions, sessionCwds: sessionCwds)
    }

    // MARK: - Heartbeat

    private func heartbeat() {
        guard !isPaused else { return }
        let snaps = Array(metricsEngine.sessions.values)
        AppState.log("heartbeat: \(snaps.count) snapshots, trackers=\(metricsEngine.trackerCount)")
        heartbeatLogger?.logSnapshots(snaps)

        // Save offsets + update file paths + cwds for UI
        if let offsets = sessionWatcher?.currentOffsets {
            OffsetCheckpoint.save(offsets)
            for (_, entry) in offsets {
                let url = URL(fileURLWithPath: entry.file)
                let sessionId = url.deletingPathExtension().lastPathComponent
                sessionFilePaths[sessionId] = entry.file
            }
        }
        if let cwds = sessionWatcher?.sessionCwds {
            for (sid, cwd) in cwds {
                sessionCwds[sid] = cwd
            }
        }
    }

    // MARK: - Actions

    func togglePause() {
        isPaused.toggle()
    }

    @Published var showingConfig = false

    func openConfig() {
        showingConfig.toggle()
    }

    func generateReport() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let heartbeatFile = InkPulseDefaults.heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
        _ = ReportGenerator.generate(from: heartbeatFile)
    }

    // MARK: - Debug Log

    static func log(_ msg: String) {
        let line = "[InkPulse \(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
        let logFile = InkPulseDefaults.inkpulseDir.appendingPathComponent("debug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let h = try? FileHandle(forWritingTo: logFile) { h.seekToEndOfFile(); h.write(data); try? h.close() }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
}
