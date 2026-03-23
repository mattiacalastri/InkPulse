import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState

    private var sortedSessions: [MetricsSnapshot] {
        appState.metricsEngine.sessions.values
            .sorted { $0.lastEventTime > $1.lastEventTime }
    }

    private var aggregateHealth: Int {
        appState.metricsEngine.aggregateHealth
    }

    private var avgCacheHit: Double {
        let snaps = Array(appState.metricsEngine.sessions.values)
        guard !snaps.isEmpty else { return 0 }
        return snaps.map(\.cacheHit).reduce(0, +) / Double(snaps.count)
    }

    private var avgErrorRate: Double {
        let snaps = Array(appState.metricsEngine.sessions.values)
        guard !snaps.isEmpty else { return 0 }
        return snaps.map(\.errorRate).reduce(0, +) / Double(snaps.count)
    }

    private var avgThinkRatio: Double {
        let snaps = Array(appState.metricsEngine.sessions.values)
        let ratios = snaps.compactMap(\.thinkOutputRatio)
        guard !ratios.isEmpty else { return 0 }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private var totalAgents: Int {
        appState.metricsEngine.sessions.values
            .map(\.subagentCount)
            .reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("🐙 InkPulse")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                if aggregateHealth >= 0 {
                    Text("\(aggregateHealth)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(healthColor(for: aggregateHealth))
                } else {
                    Text("😴 idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Session list
            if sortedSessions.isEmpty {
                Text("No active sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sortedSessions, id: \.sessionId) { snap in
                            SessionRowView(
                                snapshot: snap,
                                filePath: appState.sessionFilePaths[snap.sessionId]
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // ECG Sparkline
            if !appState.tokenHistory.isEmpty {
                SparklineView(
                    data: appState.tokenHistory,
                    color: Color(hex: "#00d4aa")
                )
                .frame(height: 40)

                Divider()
            }

            // Metrics grid 2x2
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    metricLabel("Cache", String(format: "%.0f%%", avgCacheHit * 100))
                    metricLabel("Think:Out", String(format: "%.1f", avgThinkRatio))
                }
                VStack(alignment: .leading, spacing: 4) {
                    metricLabel("Errors", String(format: "%.1f%%", avgErrorRate * 100))
                    metricLabel("Agents", "\(totalAgents)")
                }
            }

            Divider()

            // Actions
            HStack(spacing: 8) {
                Button("Report") {
                    appState.generateReport()
                }
                .buttonStyle(.bordered)

                Button(appState.isPaused ? "Resume" : "Pause") {
                    appState.togglePause()
                }
                .buttonStyle(.bordered)

                Button("Edit Config") {
                    appState.openConfig()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func metricLabel(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
        }
    }
}
