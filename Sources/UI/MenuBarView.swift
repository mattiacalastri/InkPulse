import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    @State private var isPulsing = false

    private var snaps: [MetricsSnapshot] {
        Array(appState.metricsEngine.sessions.values)
    }

    private var health: Int {
        appState.metricsEngine.aggregateHealth
    }

    private var anomaly: Anomaly? {
        appState.metricsEngine.primaryAnomaly
    }

    private var avgTokenMin: Double {
        guard !snaps.isEmpty else { return 0 }
        return snaps.map(\.tokenMin).reduce(0, +) / Double(snaps.count)
    }

    private var totalCost: Double {
        snaps.map(\.costEUR).reduce(0, +)
    }

    private var healthColor_: Color {
        if health < 0 {
            return Color(hex: "#666666")
        }
        if let anomaly = anomaly {
            switch anomaly {
            case .deepThinking:
                return Color(hex: "#4A9EFF")
            case .stall, .loop, .hemorrhage, .explosion:
                return Color(hex: "#FF4444")
            }
        }
        return healthColor(for: health)
    }

    private var pulseFrequency: Double {
        guard !snaps.isEmpty else { return 2.0 }
        return min(max(avgTokenMin / 333.0, 0.5), 3.0)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\u{1F419}")
                .font(.system(size: 12))

            if health >= 0 {
                // Health
                Text("\(health)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(healthColor_)
                    .opacity(isPulsing ? 1.0 : 0.7)
                    .animation(
                        .easeInOut(duration: 1.0 / pulseFrequency).repeatForever(autoreverses: true),
                        value: isPulsing
                    )

                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                // tok/min
                Text("\(Int(avgTokenMin))t")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                // Cost
                Text(String(format: "€%.2f", totalCost))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .onAppear {
            isPulsing = true
        }
    }
}
