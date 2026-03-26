import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {

    @Published var metricsEngine = MetricsEngine()
    @Published var tokenHistory: [Double] = []
    @Published var isPaused = false
    @Published var historyStore = HistoryStore()
    @Published var sessionFilePaths: [String: String] = [:] // sessionId → filePath
    @Published var sessionCwds: [String: String] = [:] // sessionId → cwd
    @Published var sessionBranches: [String: String] = [:] // sessionId → gitBranch
    @Published var quotaSnapshot: QuotaSnapshot?

    // MARK: - Team State
    @Published var teamConfigs: [TeamConfig] = []
    @Published var teamStates: [TeamState] = []
    @Published var unmatchedSessionIds: [String] = []

    private var heartbeatLogger: HeartbeatLogger?
    private var sessionWatcher: SessionWatcher?
    private var refreshTimer: Timer?
    private var heartbeatTimer: Timer?
    private(set) var notificationManager = NotificationManager()
    private(set) var anomalyWatcher: AnomalyWatcher?
    private var quotaFetcher: QuotaFetcher?

    private let maxTokenHistory = 300  // ~5 min at 1 sample/s

    /// Previous aggregate health for delta arrow.
    private var previousHealth: Int = -1
    /// Previous average tok/min for delta arrow.
    private var previousTokenMin: Double = 0

    /// Budget alert thresholds already triggered today (Feature 3).
    private var triggeredBudgetThresholds: Set<Double> = []
    private var budgetAlertDay: Int = -1  // day of year for reset

    // MARK: - Start

    func start() {
        let config = ConfigLoader.load()

        heartbeatLogger = HeartbeatLogger(purgeDays: config.purgeDays)

        let projectsDir = InkPulseDefaults.claudeProjectsPath

        sessionWatcher = SessionWatcher(projectsDir: projectsDir) { [weak self] events in
            Task { @MainActor in
                guard let self = self, !self.isPaused else { return }
                AppState.log("Received \(events.count) events")
                for event in events {
                    self.metricsEngine.ingest(event)
                }
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

        // Load team configuration
        teamConfigs = TeamsLoader.load()
        AppState.log("Loaded \(teamConfigs.count) teams from teams.json")

        // Quota fetcher — OAuth token already approved in Keychain
        // Silently fails if not authorized — no popups
        quotaFetcher = QuotaFetcher()
        quotaFetcher?.start { [weak self] snapshot in
            Task { @MainActor in
                self?.quotaSnapshot = snapshot
            }
        }
    }

    // MARK: - Refresh

    private func refresh() {
        guard !isPaused else { return }
        previousHealth = metricsEngine.aggregateHealth
        let oldSnaps = Array(metricsEngine.sessions.values)
        previousTokenMin = oldSnaps.isEmpty ? 0 : oldSnaps.map(\.tokenMin).reduce(0, +) / Double(oldSnaps.count)
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

        // Team matching
        refreshTeamStates()

        // Budget check (Feature 3)
        checkBudget()
    }

    // MARK: - Heartbeat

    private func heartbeat() {
        guard !isPaused else { return }
        let snaps = Array(metricsEngine.sessions.values)
        AppState.log("heartbeat: \(snaps.count) snapshots, trackers=\(metricsEngine.trackerCount)")
        heartbeatLogger?.logSnapshots(snaps, cwds: sessionCwds)

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
        if let branches = sessionWatcher?.sessionBranches {
            for (sid, branch) in branches {
                sessionBranches[sid] = branch
            }
        }
    }

    // MARK: - Budget Check (Feature 3)

    private func checkBudget() {
        let config = ConfigLoader.load()
        guard config.dailyBudgetEUR > 0 else { return }

        // Reset thresholds on new day
        let today = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        if today != budgetAlertDay {
            triggeredBudgetThresholds.removeAll()
            budgetAlertDay = today
        }

        let totalCost = Array(metricsEngine.sessions.values).map(\.costEUR).reduce(0, +)
        let fraction = totalCost / config.dailyBudgetEUR

        for threshold in config.budgetAlertThresholds.sorted() {
            if fraction >= threshold && !triggeredBudgetThresholds.contains(threshold) {
                triggeredBudgetThresholds.insert(threshold)
                let pct = Int(threshold * 100)
                notificationManager.send(
                    title: "Daily Budget \(pct)%",
                    body: String(format: "Spent €%.2f of €%.2f budget (%d%%)", totalCost, config.dailyBudgetEUR, Int(fraction * 100))
                )
            }
        }
    }

    // MARK: - Deltas

    var healthDelta: Int {
        let current = metricsEngine.aggregateHealth
        guard current >= 0, previousHealth >= 0 else { return 0 }
        return current - previousHealth
    }

    var tokenMinDelta: Double {
        let snaps = Array(metricsEngine.sessions.values)
        guard !snaps.isEmpty else { return 0 }
        let current = snaps.map(\.tokenMin).reduce(0, +) / Double(snaps.count)
        return current - previousTokenMin
    }

    // MARK: - Actions

    func togglePause() {
        isPaused.toggle()
    }

    @Published var showingConfig = false

    func openConfig() {
        showingConfig.toggle()
    }

    func reloadTeams() {
        teamConfigs = TeamsLoader.load()
        refreshTeamStates()
        AppState.log("Reloaded \(teamConfigs.count) teams")
    }

    private func refreshTeamStates() {
        let result = TeamsLoader.matchSessions(
            teams: teamConfigs,
            sessions: metricsEngine.sessions,
            sessionCwds: sessionCwds,
            previousStates: teamStates
        )
        teamStates = result.teamStates
        unmatchedSessionIds = result.unmatchedSessionIds
    }

    // MARK: - Spawn

    func spawnTeam(_ team: TeamConfig, occupiedRoleIds: Set<String>) {
        let results = TeamSpawner.spawnTeam(team, occupiedRoleIds: occupiedRoleIds)
        let succeeded = results.filter(\.success).count
        let total = results.count
        AppState.log("Spawned team \(team.name): \(succeeded)/\(total) roles")
        if succeeded > 0 {
            notificationManager.send(
                title: "Team Spawned",
                body: "\(team.name): \(succeeded) agent\(succeeded == 1 ? "" : "s") launched"
            )
        }
    }

    func spawnRole(_ role: RoleConfig, team: TeamConfig) {
        let success = TeamSpawner.spawnRole(role, team: team)
        AppState.log("Spawn \(team.name)/\(role.name): \(success ? "OK" : "FAILED")")
        if success {
            notificationManager.send(
                title: "Agent Spawned",
                body: "\(team.name)/\(role.name) is now running"
            )
        }
    }

    func forceRescan() {
        sessionWatcher?.poll()
        refresh()
        heartbeat()
        AppState.log("Force rescan triggered")
    }

    func generateReport() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let heartbeatFile = InkPulseDefaults.heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
        _ = ReportGenerator.generate(from: heartbeatFile)
    }

    // MARK: - Debug Log

    nonisolated static func log(_ msg: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "[InkPulse \(formatter.string(from: Date()))] \(msg)\n"
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
