import SwiftUI

struct ConfigView: View {
    @ObservedObject var appState: AppState

    @AppStorage("inkpulse_refresh_hz") private var refreshHz: Double = 1.0
    @AppStorage("inkpulse_heartbeat_s") private var heartbeatS: Double = 5.0
    @AppStorage("inkpulse_timeout_min") private var timeoutMin: Double = 5.0
    @AppStorage("inkpulse_tail_kb") private var tailKB: Double = 500.0
    @AppStorage("inkpulse_daily_budget") private var dailyBudget: Double = 0.0
    @AppStorage("inkpulse_sound_anomaly") private var soundOnAnomaly: Bool = true
    @State private var showingWizard = false
    @State private var showingDeckEditor = false

    private var hasTeams: Bool { !appState.teamConfigs.isEmpty }

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

                    // ── BUDGET & ALERTS ──
                    sectionHeader("Budget & Alerts")

                    configRow(
                        icon: "eurosign.circle.fill",
                        title: "Daily Budget",
                        subtitle: dailyBudget > 0 ? String(format: "€%.0f", dailyBudget) : "Disabled"
                    ) {
                        Slider(value: $dailyBudget, in: 0...50, step: 1)
                            .frame(width: 100)
                    }

                    configRow(
                        icon: "speaker.wave.2.fill",
                        title: "Sound on Anomaly",
                        subtitle: soundOnAnomaly ? "On" : "Off"
                    ) {
                        Toggle("", isOn: $soundOnAnomaly)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    Divider().padding(.vertical, 4)

                    // ── TEAMS ──
                    sectionHeader("Teams")

                    Button(action: { showingWizard = true }) {
                        Label(hasTeams ? "Edit Teams" : "Setup Teams",
                              systemImage: hasTeams ? "pencil.circle.fill" : "sparkles")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hasTeams ? .secondary : Color(hex: "#00d4aa"))
                    .controlSize(.regular)

                    if hasTeams {
                        Text("\(appState.teamConfigs.count) teams configured")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Organize your Claude Code sessions into teams with one click.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    Divider().padding(.vertical, 4)

                    // ── DECK ──
                    sectionHeader("Motivational Deck")

                    Button(action: { showingDeckEditor = true }) {
                        Label("Edit Deck", systemImage: "quote.bubble.fill")
                            .font(.system(.caption, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Text("Customize the quotes shown in the dashboard header.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    Divider().padding(.vertical, 4)

                    // ── INFO ──
                    sectionHeader("About")

                    HStack(spacing: 8) {
                        Text("🐙")
                            .font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("InkPulse v2.0.0")
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.bold)
                            Text("Control Plane for AI Agent Teams")
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
        .frame(width: 560)
        .sheet(isPresented: $showingWizard) {
            SetupWizardView(appState: appState, isPresented: $showingWizard)
        }
        .sheet(isPresented: $showingDeckEditor) {
            DeckEditorView(isPresented: $showingDeckEditor)
        }
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
