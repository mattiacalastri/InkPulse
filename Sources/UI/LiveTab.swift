import SwiftUI

struct LiveTab: View {
    @ObservedObject var appState: AppState

    // MARK: - Computed Stats

    private var snaps: [MetricsSnapshot] {
        appState.metricsEngine.sessions.values
            .sorted { $0.lastEventTime > $1.lastEventTime }
    }

    private var health: Int { appState.metricsEngine.aggregateHealth }

    private var totalCost: Double {
        snaps.map(\.costEUR).reduce(0, +)
    }

    private var avgCacheHit: Double {
        guard !snaps.isEmpty else { return 0 }
        return snaps.map(\.cacheHit).reduce(0, +) / Double(snaps.count)
    }

    private var avgErrorRate: Double {
        guard !snaps.isEmpty else { return 0 }
        return snaps.map(\.errorRate).reduce(0, +) / Double(snaps.count)
    }

    private var peakTokenMin: Double {
        appState.tokenHistory.max() ?? 0
    }

    private var avgTokenMin: Double {
        let h = appState.tokenHistory
        guard !h.isEmpty else { return 0 }
        return h.reduce(0, +) / Double(h.count)
    }

    private var uptimeMin: Double {
        guard let earliest = snaps.map(\.startTime).min() else { return 0 }
        return Date().timeIntervalSince(earliest) / 60.0
    }

    private var throughputPerAgent: Double {
        guard !snaps.isEmpty else { return 0 }
        return avgTokenMin / Double(snaps.count)
    }

    private var totalAgents: Int {
        snaps.map(\.subagentCount).reduce(0, +)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(hex: "#0a0f1a").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── HEADER ──
                header
                    .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                // ── STATS GRID ──
                statsGrid
                    .padding(.horizontal, 28).padding(.vertical, 20)

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
        .frame(minWidth: 580, minHeight: 520)
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
                        Text("🐙").font(.title)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("InkPulse")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Heartbeat Monitor for Claude Code")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(hex: "#00d4aa").opacity(0.7))
                Text("\(snaps.count) agents · \(Int(uptimeMin))m uptime")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // Health score
            if health >= 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(health)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(healthColor(for: health))
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
            dashStat("tok/min", String(format: "%.0f", avgTokenMin), color: .white)
            dashDivider()
            dashStat("peak", String(format: "%.0f", peakTokenMin), color: Color(hex: "#00d4aa"))
            dashDivider()
            dashStat("cache", String(format: "%.0f%%", avgCacheHit * 100), color: avgCacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
            dashDivider()
            dashStat("err", String(format: "%.1f%%", avgErrorRate * 100), color: avgErrorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
            dashDivider()
            dashStat("cost", String(format: "€%.2f", totalCost), color: .white)
            dashDivider()
            dashStat("agents", "\(totalAgents)", color: Color(hex: "#4A9EFF"))
            dashDivider()
            dashStat("tok/agent", String(format: "%.0f", throughputPerAgent), color: .white.opacity(0.7))
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#00d4aa").opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func dashStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func dashDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 36)
    }

    // MARK: - ECG

    private var ecgSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .font(.caption)
                Text("ECG")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("tok/min · \(appState.tokenHistory.count)s window")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
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
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(snaps.count) sessions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }

            if snaps.isEmpty {
                Text("No active agents")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(snaps, id: \.sessionId) { snap in
                            SessionRowView(
                                snapshot: snap,
                                filePath: appState.sessionFilePaths[snap.sessionId],
                                cwd: appState.sessionCwds[snap.sessionId]
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.03))
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("v1.0.0 · by Mattia Calastri · Astra Digital")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
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
