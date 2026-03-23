import SwiftUI
import AppKit

final class AppState: ObservableObject {

    @Published var metricsEngine = MetricsEngine()
    @Published var tokenHistory: [Double] = []
    @Published var isPaused = false

    private var heartbeatLogger: HeartbeatLogger?
    private var sessionWatcher: SessionWatcher?
    private var refreshTimer: Timer?
    private var heartbeatTimer: Timer?

    private let maxTokenHistory = 300  // ~5 min at 1 sample/s

    // MARK: - Start

    func start() {
        let config = ConfigLoader.load()

        heartbeatLogger = HeartbeatLogger(purgeDays: config.purgeDays)

        let projectsDir = InkPulseDefaults.claudeProjectsPath

        sessionWatcher = SessionWatcher(projectsDir: projectsDir) { [weak self] events in
            guard let self = self, !self.isPaused else { return }
            for event in events {
                self.metricsEngine.ingest(event)
            }
        }

        // Restore offsets
        let offsets = OffsetCheckpoint.load()
        sessionWatcher?.restoreOffsets(offsets)

        sessionWatcher?.start()

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
    }

    // MARK: - Refresh

    private func refresh() {
        guard !isPaused else { return }
        metricsEngine.refreshSnapshots()

        // Append average tokenMin to history for sparkline
        let snaps = Array(metricsEngine.sessions.values)
        if !snaps.isEmpty {
            let avgTokenMin = snaps.map(\.tokenMin).reduce(0, +) / Double(snaps.count)
            tokenHistory.append(avgTokenMin)
            if tokenHistory.count > maxTokenHistory {
                tokenHistory.removeFirst(tokenHistory.count - maxTokenHistory)
            }
        }
    }

    // MARK: - Heartbeat

    private func heartbeat() {
        guard !isPaused else { return }
        let snaps = Array(metricsEngine.sessions.values)
        heartbeatLogger?.logSnapshots(snaps)

        // Save offsets
        if let offsets = sessionWatcher?.currentOffsets {
            OffsetCheckpoint.save(offsets)
        }
    }

    // MARK: - Actions

    func togglePause() {
        isPaused.toggle()
    }

    func openConfig() {
        let configURL = InkPulseDefaults.configFile
        let fm = FileManager.default

        // Create default config.json if missing
        if !fm.fileExists(atPath: configURL.path) {
            try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let defaultConfig = InkPulseConfig.default
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(defaultConfig) {
                try? data.write(to: configURL, options: .atomic)
            }
        }

        NSWorkspace.shared.open(configURL)
    }

    func generateReport() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let heartbeatFile = InkPulseDefaults.heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
        _ = ReportGenerator.generate(from: heartbeatFile)
    }
}
