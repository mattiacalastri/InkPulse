import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    @State private var isPulsing = false

    private var health: Int {
        appState.metricsEngine.aggregateHealth
    }

    private var anomaly: Anomaly? {
        appState.metricsEngine.primaryAnomaly
    }

    private var iconName: String {
        if health < 0 {
            return "circle"
        }
        if let anomaly = anomaly {
            switch anomaly {
            case .deepThinking:
                return "diamond.fill"
            case .stall, .loop:
                return "exclamationmark.triangle.fill"
            case .hemorrhage, .explosion:
                return "exclamationmark.triangle.fill"
            }
        }
        return "circle.fill"
    }

    private var iconColor: Color {
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
        // Base frequency derived from average token/min across sessions
        let snaps = Array(appState.metricsEngine.sessions.values)
        guard !snaps.isEmpty else { return 2.0 }
        let avgTokenMin = snaps.map(\.tokenMin).reduce(0, +) / Double(snaps.count)
        // Map 0-1000 tok/min to 0.5-3.0 Hz
        return min(max(avgTokenMin / 333.0, 0.5), 3.0)
    }

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .animation(
                health >= 0
                    ? .easeInOut(duration: 1.0 / pulseFrequency).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}
