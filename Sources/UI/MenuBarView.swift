import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    @State private var isPulsing = false

    // Read from top-level @Published on AppState (not nested metricsEngine)
    // so MenuBarExtra label actually refreshes.
    private var health: Int { appState.menuBarHealth }
    private var avgTokenMin: Double { appState.menuBarTokenMin }
    private var totalCost: Double { appState.menuBarCost }

    private var anomaly: Anomaly? {
        appState.metricsEngine.primaryAnomaly
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
        guard avgTokenMin > 0 else { return 2.0 }
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
