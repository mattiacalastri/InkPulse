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

    // MARK: - Orchestrate State
    @Published var orchestratePhase: OrchestratePhase = .idle
    @Published var orchestrateMissions: MissionsFile?
    private var missionsWatcher: MissionsWatcher?
    private var orchestrateTimeout: Timer?

    private var heartbeatLogger: HeartbeatLogger?
    private var sessionWatcher: SessionWatcher?
    private var refreshTimer: Timer?
    private var heartbeatTimer: Timer?
    private(set) var notificationManager = NotificationManager()
    private(set) var anomalyWatcher: AnomalyWatcher?
    private var quotaFetcher: QuotaFetcher?

    // MARK: - WebSocket + Events
    private(set) var wsServer: WSServer?
    @Published var sessionRegistry = SessionRegistry()
    private var eventDetector: EventDetector?

    // MARK: - MCP Hub (Phase 4)
    @Published var mcpServerManager = MCPServerManager()
    @Published var mcpProxy = MCPProxy()
    @Published var mcpHubEnabled = false

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

        // WebSocket server
        wsServer = WSServer()
        wsServer?.onStatusReceived = { [weak self] status in
            Task { @MainActor in self?.sessionRegistry.updateStatus(status) }
        }
        wsServer?.onSessionConnected = { [weak self] sessionId in
            Task { @MainActor in self?.sessionRegistry.register(sessionId: sessionId) }
        }
        wsServer?.onSessionDisconnected = { [weak self] sessionId in
            Task { @MainActor in self?.sessionRegistry.unregister(sessionId: sessionId) }
        }
        wsServer?.start()

        // Event detector
        eventDetector = EventDetector(notificationManager: notificationManager)

        // MCP Hub — load config, optionally launch
        mcpServerManager.loadConfig()
        AppState.log("MCPHub: \(mcpServerManager.totalCount) servers loaded")

        // Quota fetcher — file-only token, no popups
        quotaFetcher = QuotaFetcher()
        quotaFetcher?.start { [weak self] snapshot in
            Task { @MainActor in
                self?.quotaSnapshot = snapshot
            }
        }
    }

    // MARK: - Refresh

    // MARK: - Menu Bar Values (top-level @Published so MenuBarExtra label refreshes)
    @Published var menuBarHealth: Int = -1
    @Published var menuBarTokenMin: Double = 0
    @Published var menuBarCost: Double = 0
    /// Formatted string for menu bar label — MenuBarExtra only reliably updates with direct Text binding.
    @Published var menuBarLabel: String = "\u{1F419}"

    private func refresh() {
        guard !isPaused else { return }
        previousHealth = metricsEngine.aggregateHealth
        let oldSnaps = Array(metricsEngine.sessions.values)
        previousTokenMin = oldSnaps.isEmpty ? 0 : oldSnaps.map(\.tokenMin).reduce(0, +) / Double(oldSnaps.count)
        metricsEngine.refreshSnapshots()

        // Propagate to top-level @Published for MenuBarExtra (nested ObservableObject won't trigger label refresh)
        menuBarHealth = metricsEngine.aggregateHealth
        let currentSnaps = Array(metricsEngine.sessions.values)
        menuBarTokenMin = currentSnaps.isEmpty ? 0 : currentSnaps.map(\.tokenMin).reduce(0, +) / Double(currentSnaps.count)
        menuBarCost = currentSnaps.map(\.costEUR).reduce(0, +)

        // Format menu bar label — MenuBarExtra only updates reliably via direct Text binding
        if menuBarHealth >= 0 {
            var label = "\u{1F419} \(menuBarHealth) · \(Int(menuBarTokenMin))t · €\(String(format: "%.2f", menuBarCost))"
            // Show weekly quota in status bar when critical (>80%)
            if let sd = quotaSnapshot?.sevenDay, sd.usedPercent > 0.80 {
                label += " · \(Int(sd.utilization))%w"
            }
            menuBarLabel = label
        } else {
            menuBarLabel = "\u{1F419}"
        }

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

        // Event detection (deploy, errors, idle)
        eventDetector?.check(sessions: metricsEngine.sessions, sessionCwds: sessionCwds)

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

        // Dynamic mode: always show team view when auto-grouped teams exist
        // This ensures the org-chart UI appears even without teams.json
        hasDynamicTeams = teamConfigs.isEmpty && !teamStates.isEmpty
    }

    /// True when teams are auto-generated from session cwds (no static teams.json).
    @Published var hasDynamicTeams = false

    // MARK: - MCP Hub Control

    func startMCPHub() {
        guard !mcpHubEnabled else { return }
        mcpServerManager.launchAll()
        mcpProxy.start(serverManager: mcpServerManager)
        mcpHubEnabled = true
        AppState.log("MCPHub: started (\(mcpServerManager.runningCount)/\(mcpServerManager.totalCount) servers)")
    }

    func stopMCPHub() {
        mcpProxy.stop()
        mcpServerManager.stopAll()
        mcpHubEnabled = false
        AppState.log("MCPHub: stopped")
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

    // MARK: - Orchestrate

    func orchestrate() {
        guard orchestratePhase == .idle || orchestratePhase.isFailed else {
            AppState.log("Orchestrate: already running, ignoring")
            return
        }

        // Clean up any previous missions file
        let missionsPath = InkPulseDefaults.inkpulseDir.appendingPathComponent("missions.json")
        try? FileManager.default.removeItem(at: missionsPath)

        orchestratePhase = .thinking
        orchestrateMissions = nil

        // Start watching for missions.json
        missionsWatcher?.stop()
        missionsWatcher = MissionsWatcher(directory: InkPulseDefaults.inkpulseDir) { [weak self] file in
            Task { @MainActor in
                self?.onMissionsReady(file)
            }
        }
        missionsWatcher?.start()

        // Spawn orchestrator
        let success = OrchestrateSpawner.spawnOrchestrator()
        if !success {
            orchestratePhase = .failed("Failed to spawn orchestrator Terminal")
            missionsWatcher?.stop()
            return
        }

        // Timeout: 120s
        orchestrateTimeout?.invalidate()
        orchestrateTimeout = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor [weak strongSelf] in
                guard let self = strongSelf, self.orchestratePhase == .thinking else { return }
                self.orchestratePhase = .failed("Orchestrator did not produce missions in 120s")
                self.missionsWatcher?.stop()
                AppState.log("Orchestrate: timeout")
            }
        }

        notificationManager.send(
            title: "Orchestrator Spawned",
            body: "The Polpo is reading the garden..."
        )
        AppState.log("Orchestrate: started, waiting for missions.json")
    }

    private func onMissionsReady(_ file: MissionsFile) {
        orchestrateTimeout?.invalidate()
        orchestrateMissions = file
        AppState.log("Orchestrate: received \(file.missions.count) missions — \(file.reasoning.prefix(80))")

        orchestratePhase = .spawning(0, file.missions.count)

        let succeeded = OrchestrateSpawner.spawnMissions(file) { [weak self] completed, total in
            self?.orchestratePhase = .spawning(completed, total)
        }

        orchestratePhase = .active
        missionsWatcher?.cleanup()
        missionsWatcher?.stop()

        notificationManager.send(
            title: "Orchestration Active",
            body: "\(succeeded)/\(file.missions.count) agents spawned. Reasoning: \(file.reasoning.prefix(60))..."
        )
        AppState.log("Orchestrate: active — \(succeeded)/\(file.missions.count) agents")
    }

    func stopOrchestrate() {
        orchestratePhase = .idle
        orchestrateMissions = nil
        orchestrateTimeout?.invalidate()
        missionsWatcher?.cleanup()
        missionsWatcher?.stop()
        AppState.log("Orchestrate: stopped")
    }

    func killSession(cwd: String?, sessionId: String) {
        guard let pid = ProcessResolver.findPID(for: cwd) else {
            AppState.log("Kill failed: no PID found for \(sessionId)")
            notificationManager.send(
                title: "Kill Failed",
                body: "Could not find process for session \(String(sessionId.prefix(8)))"
            )
            return
        }
        SessionKiller.kill(pid: pid)
        AppState.log("Kill requested for \(sessionId) (PID \(pid))")
        notificationManager.send(
            title: "Agent Stopped",
            body: "Sent SIGTERM to PID \(pid)"
        )
    }

    func sendTask(_ prompt: String, to sessionId: String) {
        let message = WSOutbound.command(WSCommandMessage(action: "task", prompt: prompt))
        wsServer?.send(message, to: sessionId)
        AppState.log("Sent task to \(sessionId): \(prompt.prefix(50))")
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
