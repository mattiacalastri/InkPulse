import SwiftUI

struct LiveTab: View {
    @ObservedObject var appState: AppState

    @State private var expandedSessionId: String?
    @State private var showStopConfirm = false

    // MARK: - Stats

    private var stats: DashboardStats { DashboardStats(appState: appState) }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── HEADER ──
                header
                    .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)

                Divider().overlay(.white.opacity(0.06))

                // ── STATS GRID ──
                statsGrid
                    .padding(.horizontal, 28).padding(.vertical, 20)

                // ── DAILY BUDGET BAR (Feature 3) ──
                if stats.config.dailyBudgetEUR > 0 {
                    dailyBudgetBar
                        .padding(.horizontal, 28).padding(.bottom, 12)
                }

                // ── QUOTA BARS ──
                if let q = stats.quotaSnapshot {
                    quotaSection(q)
                        .padding(.horizontal, 28).padding(.bottom, 12)
                }

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                // ── ECG ──
                ecgSection
                    .padding(.horizontal, 28).padding(.vertical, 20)

                Spacer(minLength: 0)

                // ── FOOTER ──
                footer
                    .padding(.horizontal, 28).padding(.bottom, 20)
            }
        }
        .frame(minWidth: 580, minHeight: 640)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            // App icon from bundle
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#00d4aa").opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2)
                            .foregroundStyle(Color(hex: "#00d4aa"))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("InkPulse")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(appState.teamConfigs.isEmpty && !appState.hasDynamicTeams ? "Heartbeat Monitor for Claude Code" : "Control Plane for AI Agent Teams")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(hex: "#00d4aa").opacity(0.7))
                Text("\(stats.snaps.count) agents · \(Int(stats.uptimeMin))m uptime")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            orchestrateButton

            // EGI glyph (global)
            if appState.metricsEngine.globalEGIState > .dormant {
                VStack(alignment: .center, spacing: 2) {
                    EGIGlyphView(state: appState.metricsEngine.globalEGIState, size: 32)
                    if appState.metricsEngine.egiWindowCount > 1 {
                        Text("\(appState.metricsEngine.egiWindowCount) windows")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color(hex: "#FFD700").opacity(0.6))
                    }
                }
                .padding(.trailing, 8)
            }

            // Health score
            if stats.health >= 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(stats.health)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(healthColor(for: stats.health))
                    if appState.healthDelta != 0 {
                        Text(appState.healthDelta > 0 ? "\u{2191}\(appState.healthDelta)" : "\u{2193}\(abs(appState.healthDelta))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(appState.healthDelta > 0 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
                    }
                    Text("HEALTH")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            } else {
                Text("IDLE")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Orchestrate Button

    private var orchestrateButton: some View {
        Group {
            switch appState.orchestratePhase {
            case .idle:
                Button(action: { appState.orchestrate() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12))
                        Text("Orchestrate")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#00d4aa").opacity(0.12))
                            .overlay(Capsule().stroke(Color(hex: "#00d4aa").opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.borderless)

            case .thinking:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color(hex: "#00d4aa"))
                    Text("Thinking...")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "#00d4aa"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(hex: "#00d4aa").opacity(0.08)))

            case .spawning(let done, let total):
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color(hex: "#FFD700"))
                    Text("Spawning \(done)/\(total)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "#FFD700"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(hex: "#FFD700").opacity(0.08)))

            case .active:
                Button(action: { showStopConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("\(appState.orchestrateMissions?.missions.count ?? 0) Active")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#00d4aa").opacity(0.15))
                            .overlay(Capsule().stroke(Color(hex: "#00d4aa").opacity(0.4), lineWidth: 1))
                    )
                }
                .buttonStyle(.borderless)
                .alert("Stop Orchestration?", isPresented: $showStopConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Stop", role: .destructive) { appState.stopOrchestrate() }
                } message: {
                    Text("This resets the orchestration state. Running agents will continue but won't be tracked as an orchestrated team.")
                }

            case .failed(let reason):
                Button(action: { appState.orchestrate() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text("Retry")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "#FF4444"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(hex: "#FF4444").opacity(0.1)))
                }
                .buttonStyle(.borderless)
                .help(reason)
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 0) {
            dashStat("speed", String(format: "%.0f", stats.avgTokenMin) + trendArrow(appState.tokenMinDelta), color: .white)
            dashDivider()
            dashStat("peak speed", String(format: "%.0f", stats.peakTokenMin), color: Color(hex: "#00d4aa"))
            dashDivider()
            dashStat("cached", String(format: "%.0f%%", stats.avgCacheHit * 100), color: stats.avgCacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
            dashDivider()
            dashStat("errors", String(format: "%.1f%%", stats.avgErrorRate * 100), color: stats.avgErrorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
            dashDivider()
            dashStat("cost", String(format: "€%.2f", stats.totalCost), color: .white)
            dashDivider()
            dashStat("memory", stats.avgContextPercent > 0 ? String(format: "%.0f%%", stats.avgContextPercent * 100) : "—", color: contextStatColor(stats.avgContextPercent))
            dashDivider()
            dashStat("helpers", "\(stats.totalAgents)", color: Color(hex: "#4A9EFF"))
            dashDivider()
            dashStat("per agent", String(format: "%.0f", stats.throughputPerAgent), color: .white.opacity(0.7))

            if let used = stats.quotaUsedDisplay, let remaining = stats.quotaRemainingPercent {
                dashDivider()
                dashStat(stats.planName ?? "plan", used, color: quotaStatColor(remaining))
            } else if let bp = stats.budgetPercent {
                dashDivider()
                dashStat("budget", String(format: "%.0f%%", bp * 100), color: budgetStatColor(bp))
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func dashStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private func dashDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 36)
    }

    private func contextStatColor(_ percent: Double) -> Color {
        if percent <= 0 { return .white.opacity(0.3) }
        return contextColor(for: percent)
    }

    private func quotaStatColor(_ percent: Double) -> Color {
        if percent > 0.50 { return Color(hex: "#00d4aa") }
        if percent > 0.20 { return Color(hex: "#FFA500") }
        return Color(hex: "#FF4444")
    }

    private func budgetStatColor(_ percent: Double) -> Color {
        if percent < 0.60 { return Color(hex: "#00d4aa") }
        if percent < 0.80 { return Color(hex: "#FFA500") }
        return Color(hex: "#FF4444")
    }

    private func trendArrow(_ delta: Double) -> String {
        if delta > 20 { return " \u{2191}" }
        if delta < -20 { return " \u{2193}" }
        return ""
    }

    // MARK: - Daily Budget Bar (Feature 3)

    // MARK: - Quota Section

    private func quotaSection(_ q: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API QUOTA")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(q.plan.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#00d4aa"))
            }

            if let fh = q.fiveHour {
                quotaBar(label: "5h limit", tier: fh)
            }
            if let sd = q.sevenDay {
                quotaBar(label: "weekly limit", tier: sd)
            }
            if let opus = q.sevenDayOpus {
                quotaBar(label: "opus model", tier: opus)
            }
            if let sonnet = q.sevenDaySonnet {
                quotaBar(label: "sonnet model", tier: sonnet)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#00d4aa").opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func quotaBar(label: String, tier: QuotaTier) -> some View {
        let used = tier.usedPercent
        let barColor: Color = {
            if used < 0.60 { return Color(hex: "#00d4aa") }
            if used < 0.80 { return Color(hex: "#FFA500") }
            return Color(hex: "#FF4444")
        }()

        return VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.0f%%", tier.utilization))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(barColor)
                if let reset = tier.resetsAt {
                    Text(formatResetTime(reset))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(max(used, 0), 1.0)))
                    // Deficit indicator: red tick at 100% if over limit
                    if used > 1.0 {
                        Rectangle()
                            .fill(Color(hex: "#FF4444"))
                            .frame(width: 2, height: 8)
                            .offset(x: geo.size.width - 1)
                    }
                }
            }
            .frame(height: 5)
        }
    }

    private func formatResetTime(_ date: Date) -> String {
        let delta = date.timeIntervalSince(Date())
        if delta <= 0 { return "now" }
        let hours = Int(delta) / 3600
        let minutes = (Int(delta) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remH = hours % 24
            return "\(days)d \(remH)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var dailyBudgetBar: some View {
        let budget = stats.config.dailyBudgetEUR
        let spent = stats.totalCost
        let fraction = budget > 0 ? spent / budget : 0
        let budgetColor: Color = {
            if fraction < 0.60 { return Color(hex: "#00d4aa") }
            if fraction < 0.80 { return Color(hex: "#FFA500") }
            return Color(hex: "#FF4444")
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("DAILY BUDGET")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(String(format: "€%.2f / €%.2f", spent, budget))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(budgetColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(budgetColor)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1.0)))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#00d4aa").opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - ECG

    private var ecgSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .font(.caption)
                Text("ECG")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("tok/min · \(appState.tokenHistory.count)s window")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }

            if appState.tokenHistory.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.02))
                    .frame(height: 80)
                    .overlay(
                        Text("Waiting for data...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                    )
            } else {
                SparklineView(
                    data: appState.tokenHistory,
                    color: Color(hex: "#00d4aa")
                )
                .frame(height: 80)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.02))
                )
            }
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .font(.caption)
                Text(appState.teamStates.isEmpty ? "ACTIVE AGENTS" : "TEAMS")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                let teamCount = appState.teamStates.count
                if teamCount > 0 {
                    Text("\(teamCount) groups \u{00B7} \(stats.snaps.count) sessions")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                } else {
                    Text("\(stats.snaps.count) sessions")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }

            if appState.teamConfigs.isEmpty && !appState.hasDynamicTeams {
                flatAgentsContent
            } else {
                teamAgentsContent
            }
        }
    }

    private var teamAgentsContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(appState.teamStates) { team in
                    TeamSectionView(
                        teamState: team,
                        sessions: appState.metricsEngine.sessions,
                        sessionCwds: appState.sessionCwds,
                        sessionBranches: appState.sessionBranches,
                        sessionFilePaths: appState.sessionFilePaths,
                        expandedSessionId: $expandedSessionId,
                        isPopover: false,
                        onSpawnTeam: { config, occupied in
                            appState.spawnTeam(config, occupiedRoleIds: occupied)
                        },
                        onSpawnRole: { role, config in
                            appState.spawnRole(role, team: config)
                        },
                        onKillSession: { cwd, sessionId in
                            appState.killSession(cwd: cwd, sessionId: sessionId)
                        },
                        wsConnected: appState.wsServer?.connectedSessionIds ?? []
                    )
                }

                // Unmatched sessions
                let unmatchedSnaps = stats.snaps.filter { appState.unmatchedSessionIds.contains($0.sessionId) }
                if !unmatchedSnaps.isEmpty {
                    liveUnmatchedSection(snaps: unmatchedSnaps)
                }

                // Expanded detail panel
                if let expandedId = expandedSessionId,
                   let snap = stats.snaps.first(where: { $0.sessionId == expandedId }) {
                    AgentDetailPanel(
                        snapshot: snap,
                        cwd: appState.sessionCwds[snap.sessionId]
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(maxHeight: 500)
    }

    private func liveUnmatchedSection(snaps: [MetricsSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("OTHER")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
            .padding(.vertical, 4)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(snaps, id: \.sessionId) { snap in
                    AgentCardView(
                        snapshot: snap,
                        filePath: appState.sessionFilePaths[snap.sessionId],
                        cwd: appState.sessionCwds[snap.sessionId],
                        gitBranch: appState.sessionBranches[snap.sessionId],
                        isExpanded: expandedSessionId == snap.sessionId,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expandedSessionId = expandedSessionId == snap.sessionId ? nil : snap.sessionId
                            }
                        },
                        onKill: {
                            appState.killSession(
                                cwd: appState.sessionCwds[snap.sessionId],
                                sessionId: snap.sessionId
                            )
                        }
                    )
                }
            }
        }
    }

    private var flatAgentsContent: some View {
        Group {
            if stats.snaps.isEmpty {
                Text("No active agents")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ],
                            spacing: 10
                        ) {
                            ForEach(stats.snaps, id: \.sessionId) { snap in
                                AgentCardView(
                                    snapshot: snap,
                                    filePath: appState.sessionFilePaths[snap.sessionId],
                                    cwd: appState.sessionCwds[snap.sessionId],
                                    gitBranch: appState.sessionBranches[snap.sessionId],
                                    isExpanded: expandedSessionId == snap.sessionId,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            expandedSessionId = expandedSessionId == snap.sessionId ? nil : snap.sessionId
                                        }
                                    },
                                    onKill: {
                                        appState.killSession(
                                            cwd: appState.sessionCwds[snap.sessionId],
                                            sessionId: snap.sessionId
                                        )
                                    }
                                )
                            }
                        }

                        if let expandedId = expandedSessionId,
                           let snap = stats.snaps.first(where: { $0.sessionId == expandedId }) {
                            AgentDetailPanel(
                                snapshot: snap,
                                cwd: appState.sessionCwds[snap.sessionId]
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .frame(maxHeight: 500)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("v2.3.0 · InkPulse")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
            Button(action: { appState.openConfig() }) {
                Label("Config", systemImage: "gearshape.fill")
                    .font(.system(.caption, design: .rounded))
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: "#00d4aa"))
            .controlSize(.small)
        }
    }
}
