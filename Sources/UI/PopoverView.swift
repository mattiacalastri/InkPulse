import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState

    @State private var expandedSessionId: String?

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

    private var totalAgents: Int {
        snaps.map(\.subagentCount).reduce(0, +)
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
                    Text("\(snaps.count) agents · \(Int(uptimeMin))m uptime")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // EGI glyph (global)
                if appState.metricsEngine.globalEGIState > .dormant {
                    EGIGlyphView(state: appState.metricsEngine.globalEGIState, size: 20)
                        .padding(.trailing, 4)
                }

                if health >= 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(health)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(healthColor(for: health))
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

            // ── STATS STRIP ──
            HStack(spacing: 0) {
                statCell("tok/min", String(format: "%.0f", avgTokenMin), color: .primary)
                statDivider()
                statCell("peak", String(format: "%.0f", peakTokenMin), color: Color(hex: "#00d4aa"))
                statDivider()
                statCell("cache", String(format: "%.0f%%", avgCacheHit * 100), color: avgCacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
                statDivider()
                statCell("err", String(format: "%.1f%%", avgErrorRate * 100), color: avgErrorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
                statDivider()
                statCell("cost", String(format: "€%.2f", totalCost), color: .primary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

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

            // ── AGENTS ──
            if snaps.isEmpty {
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
                            ForEach(snaps, id: \.sessionId) { snap in
                                AgentCardView(
                                    snapshot: snap,
                                    filePath: appState.sessionFilePaths[snap.sessionId],
                                    cwd: appState.sessionCwds[snap.sessionId],
                                    isExpanded: expandedSessionId == snap.sessionId,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            expandedSessionId = expandedSessionId == snap.sessionId ? nil : snap.sessionId
                                        }
                                    }
                                )
                            }
                        }

                        // Expanded detail panel (full-width, below grid)
                        if let expandedId = expandedSessionId,
                           let snap = snaps.first(where: { $0.sessionId == expandedId }) {
                            AgentDetailPanel(
                                snapshot: snap,
                                cwd: appState.sessionCwds[snap.sessionId]
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .frame(height: 350)
            }

            Divider().padding(.horizontal, 8)

            // ── STATS FOOTER ──
            HStack(spacing: 0) {
                statMini("agents", "\(totalAgents)")
                statMini("sessions", "\(snaps.count)")
                statMini("tok/agent", String(format: "%.0f", throughputPerAgent))
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
}
