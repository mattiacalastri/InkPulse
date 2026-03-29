import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState

    @State private var expandedSessionId: String?

    private var agentsScrollHeight: CGFloat {
        let cardHeight: CGFloat = 120
        let rows = ceil(Double(stats.snaps.count) / 2.0)
        let expandOffset: CGFloat = expandedSessionId != nil ? 180 : 0
        let computed = CGFloat(rows) * cardHeight + 20 + expandOffset
        return min(max(computed, 180), 500)
    }

    // MARK: - Stats

    private var stats: DashboardStats { DashboardStats(appState: appState) }

    private var headerSubtitle: String {
        let teamCount = appState.teamStates.count
        if teamCount > 0 {
            return "\(teamCount) groups \u{00B7} \(stats.snaps.count) agents \u{00B7} \(Int(stats.uptimeMin))m uptime"
        }
        return "\(stats.snaps.count) agents \u{00B7} \(Int(stats.uptimeMin))m uptime"
    }

    // MARK: - Body

    var body: some View {
        if appState.showingConfig {
            ConfigView(appState: appState)
        } else {
            mainView
        }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── HEADER ──
            HStack(alignment: .center) {
                // App icon from bundle
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(Color(hex: "#00d4aa"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("InkPulse")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(headerSubtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button(action: { appState.forceRescan() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#00d4aa"))
                }
                .buttonStyle(.borderless)
                .help("Sync refresh")

                // EGI glyph (global)
                if appState.metricsEngine.globalEGIState > .dormant {
                    EGIGlyphView(state: appState.metricsEngine.globalEGIState, size: 20)
                        .padding(.trailing, 4)
                }

                if stats.health >= 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(stats.health)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(healthColor(for: stats.health))
                        Text("HEALTH")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("IDLE")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            // ── PROMPT BOX ──
            PromptBoxView()

            // ── STATS STRIP ──
            HStack(spacing: 0) {
                statCell("tok/min", String(format: "%.0f", stats.avgTokenMin), color: .primary)
                statDivider()
                statCell("peak", String(format: "%.0f", stats.peakTokenMin), color: Color(hex: "#00d4aa"))
                statDivider()
                statCell("cache", String(format: "%.0f%%", stats.avgCacheHit * 100), color: stats.avgCacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
                statDivider()
                statCell("err", String(format: "%.1f%%", stats.avgErrorRate * 100), color: stats.avgErrorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
                statDivider()
                statCell("cost", String(format: "€%.2f", stats.totalCost), color: .primary)

                if let used = stats.quotaUsedDisplay, let remaining = stats.quotaRemainingPercent {
                    statDivider()
                    statCell(stats.planName ?? "plan", used, color: quotaColor(remaining))
                } else if let bp = stats.budgetPercent {
                    statDivider()
                    statCell("budget", String(format: "%.0f%%", bp * 100), color: budgetColor(bp))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            // ── TOOL BREAKDOWN ──
            if !stats.toolBreakdown.isEmpty {
                toolBreakdownStrip
            }

            // ── ECG ──
            if !appState.tokenHistory.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("ECG")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("tok/min · \(appState.tokenHistory.count)s window")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    SparklineView(
                        data: appState.tokenHistory,
                        color: Color(hex: "#00d4aa")
                    )
                    .frame(height: 44)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }

            Divider().padding(.horizontal, 8)

            // ── TEAMS + AGENTS ──
            if appState.teamConfigs.isEmpty && !appState.hasDynamicTeams {
                // No sessions — show flat agent list
                flatAgentList
            } else {
                // Team-based view (static from teams.json OR dynamic from cwd auto-grouping)
                teamAgentList
            }

            Divider().padding(.horizontal, 8)

            // ── STATS FOOTER ──
            HStack(spacing: 0) {
                statMini("agents", "\(stats.totalAgents)")
                statMini("sessions", "\(stats.snaps.count)")
                statMini("tok/agent", String(format: "%.0f", stats.throughputPerAgent))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 4)

            Divider().padding(.horizontal, 8)

            // ── ACTIONS ──
            HStack(spacing: 12) {
                Button(action: { appState.generateReport() }) {
                    Label("Report", systemImage: "doc.text.fill")
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: { appState.togglePause() }) {
                    Label(appState.isPaused ? "Resume" : "Pause", systemImage: appState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: { appState.openConfig() }) {
                    Label("Config", systemImage: "gearshape.fill")
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            // ── QUIT ──
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit InkPulse", systemImage: "xmark.circle.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.bottom, 6)
        }
        .frame(width: 560)
    }

    // MARK: - Components

    private func statCell(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func quotaColor(_ percent: Double) -> Color {
        if percent > 0.50 { return Color(hex: "#00d4aa") }
        if percent > 0.20 { return Color(hex: "#FFA500") }
        return Color(hex: "#FF4444")
    }

    private func budgetColor(_ percent: Double) -> Color {
        if percent < 0.60 { return Color(hex: "#00d4aa") }
        if percent < 0.80 { return Color(hex: "#FFA500") }
        return Color(hex: "#FF4444")
    }

    private func statDivider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private func statMini(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.trailing, 8)
    }

    // MARK: - Tool Breakdown

    private var toolBreakdownStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tools")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.totalToolCount) total")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 0) {
                let top = Array(stats.toolBreakdown.prefix(6))
                ForEach(Array(top.enumerated()), id: \.offset) { idx, entry in
                    if idx > 0 {
                        Text(" · ")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(entry.name):\(entry.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(toolColor(for: entry.name))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
    }

    private func toolColor(for name: String) -> Color {
        switch name {
        case "Read": return Color(hex: "#4A9EFF")
        case "Edit", "Write": return Color(hex: "#00d4aa")
        case "Bash": return Color(hex: "#FFA500")
        case "Grep", "Glob": return Color(hex: "#B388FF")
        case "Agent": return Color(hex: "#FF6B9D")
        default: return .secondary
        }
    }

    // MARK: - Team Agent List

    private var teamAgentList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(appState.teamStates) { team in
                    TeamSectionView(
                        teamState: team,
                        sessions: appState.metricsEngine.sessions,
                        sessionCwds: appState.sessionCwds,
                        sessionBranches: appState.sessionBranches,
                        sessionFilePaths: appState.sessionFilePaths,
                        expandedSessionId: $expandedSessionId,
                        isPopover: true,
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

                // Unmatched sessions (not belonging to any team)
                if !unmatchedSnaps.isEmpty {
                    unmatchedSection
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
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(height: agentsScrollHeight)
    }

    // MARK: - Flat Agent List (legacy, when no teams configured)

    private var flatAgentList: some View {
        Group {
            if stats.snaps.isEmpty {
                Text("No active agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ],
                            spacing: 8
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
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .frame(height: agentsScrollHeight)
            }
        }
    }

    // MARK: - Unmatched Sessions

    private var unmatchedSnaps: [MetricsSnapshot] {
        stats.snaps.filter { appState.unmatchedSessionIds.contains($0.sessionId) }
    }

    private var unmatchedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text("Other")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(unmatchedSnaps, id: \.sessionId) { snap in
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
}
