import SwiftUI

struct LiveTab: View {
    @ObservedObject var appState: AppState

    @State private var expandedSessionId: String?

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

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                // ── ECG ──
                ecgSection
                    .padding(.horizontal, 28).padding(.vertical, 20)

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                // ── AGENTS ──
                agentsSection
                    .padding(.horizontal, 28).padding(.vertical, 16)

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
                Text("Heartbeat Monitor for Claude Code")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(hex: "#00d4aa").opacity(0.7))
                Text("\(stats.snaps.count) agents · \(Int(stats.uptimeMin))m uptime")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

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

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 0) {
            dashStat("tok/min", String(format: "%.0f", stats.avgTokenMin) + trendArrow(appState.tokenMinDelta), color: .white)
            dashDivider()
            dashStat("peak", String(format: "%.0f", stats.peakTokenMin), color: Color(hex: "#00d4aa"))
            dashDivider()
            dashStat("cache", String(format: "%.0f%%", stats.avgCacheHit * 100), color: stats.avgCacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
            dashDivider()
            dashStat("err", String(format: "%.1f%%", stats.avgErrorRate * 100), color: stats.avgErrorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
            dashDivider()
            dashStat("cost", String(format: "€%.2f", stats.totalCost), color: .white)
            dashDivider()
            dashStat("ctx", stats.avgContextPercent > 0 ? String(format: "%.0f%%", stats.avgContextPercent * 100) : "—", color: contextStatColor(stats.avgContextPercent))
            dashDivider()
            dashStat("subs", "\(stats.totalAgents)", color: Color(hex: "#4A9EFF"))
            dashDivider()
            dashStat("tok/agent", String(format: "%.0f", stats.throughputPerAgent), color: .white.opacity(0.7))
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

    private func trendArrow(_ delta: Double) -> String {
        if delta > 20 { return " \u{2191}" }
        if delta < -20 { return " \u{2193}" }
        return ""
    }

    // MARK: - Daily Budget Bar (Feature 3)

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
                Text("ACTIVE AGENTS")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(stats.snaps.count) sessions")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }

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
            Text("v1.3.0 · by Mattia Calastri · Astra Digital")
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
