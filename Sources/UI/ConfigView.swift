import SwiftUI

struct ConfigView: View {
    @ObservedObject var appState: AppState

    @AppStorage("inkpulse_refresh_hz") private var refreshHz: Double = 1.0
    @AppStorage("inkpulse_heartbeat_s") private var heartbeatS: Double = 5.0
    @AppStorage("inkpulse_timeout_min") private var timeoutMin: Double = 5.0
    @AppStorage("inkpulse_tail_kb") private var tailKB: Double = 500.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Button(action: { appState.showingConfig = false }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Text("Settings")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── MONITORING ──
                    sectionHeader("Monitoring")

                    configRow(
                        icon: "bolt.fill",
                        title: "Refresh Rate",
                        subtitle: "\(String(format: "%.0f", refreshHz)) Hz"
                    ) {
                        Slider(value: $refreshHz, in: 0.5...5, step: 0.5)
                            .frame(width: 100)
                    }

                    configRow(
                        icon: "heart.fill",
                        title: "Heartbeat Interval",
                        subtitle: "\(String(format: "%.0f", heartbeatS))s"
                    ) {
                        Slider(value: $heartbeatS, in: 1...30, step: 1)
                            .frame(width: 100)
                    }

                    configRow(
                        icon: "clock.fill",
                        title: "Session Timeout",
                        subtitle: "\(String(format: "%.0f", timeoutMin)) min"
                    ) {
                        Slider(value: $timeoutMin, in: 1...30, step: 1)
                            .frame(width: 100)
                    }

                    configRow(
                        icon: "doc.text.fill",
                        title: "Tail Size",
                        subtitle: "\(String(format: "%.0f", tailKB)) KB"
                    ) {
                        Slider(value: $tailKB, in: 100...2000, step: 100)
                            .frame(width: 100)
                    }

                    Divider().padding(.vertical, 4)

                    // ── INFO ──
                    sectionHeader("About")

                    HStack(spacing: 8) {
                        Text("🐙")
                            .font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("InkPulse v0.1.0")
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.bold)
                            Text("Heartbeat Monitor for Claude Code")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("by Mattia Calastri")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // ── DATA ──
                    sectionHeader("Data")

                    Button(action: { openHeartbeatDir() }) {
                        Label("Open Heartbeat Logs", systemImage: "folder.fill")
                            .font(.system(.caption, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button(action: { openReportsDir() }) {
                        Label("Open Reports", systemImage: "doc.richtext.fill")
                            .font(.system(.caption, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .frame(width: 340)
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
    }

    private func configRow<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color(hex: "#00d4aa"))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }

    private func openHeartbeatDir() {
        NSWorkspace.shared.open(InkPulseDefaults.heartbeatDir)
    }

    private func openReportsDir() {
        NSWorkspace.shared.open(InkPulseDefaults.reportsDir)
    }
}
