import SwiftUI
import AppKit

// MARK: - Breathing Indicator

/// A living circle that breathes when the agent is active.
struct BreathingDot: View {
    let color: Color
    let isActive: Bool
    @State private var phase = false

    var body: some View {
        ZStack {
            // Outer breath ring (only when active)
            if isActive {
                Circle()
                    .stroke(color.opacity(phase ? 0.4 : 0.0), lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .scaleEffect(phase ? 1.3 : 0.8)
            }

            // Core dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .scaleEffect(isActive && phase ? 1.15 : 1.0)
        }
        .frame(width: 18, height: 18)
        .onAppear { startBreathing() }
        .onChange(of: isActive) { _, _ in startBreathing() }
    }

    private func startBreathing() {
        guard isActive else {
            phase = false
            return
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            phase = true
        }
    }
}

// MARK: - Agent Card View

/// Each card is an agent — a teammate, not a metric.
struct AgentCardView: View {
    let snapshot: MetricsSnapshot
    let filePath: String?
    let cwd: String?
    let gitBranch: String?
    let isExpanded: Bool
    let onTap: () -> Void
    var onKill: (() -> Void)?
    @State private var showKillConfirm = false

    private var mood: (emoji: String, status: String, color: Color) {
        agentMood(for: snapshot)
    }

    private var pillar: PillarInfo {
        PillarInfo.from(cwd: cwd, inferredProject: snapshot.inferredProject)
    }

    private var isAgentActive: Bool {
        let idle = Date().timeIntervalSince(snapshot.lastEventTime)
        return idle < 30 && snapshot.tokenMin > 50
    }

    /// Human-readable status that tells a story
    private var statusVerb: String {
        let idle = Date().timeIntervalSince(snapshot.lastEventTime)
        if idle > 120 { return "Sleeping" }
        if idle > 30 { return "Waiting for input" }
        if snapshot.subagentCount > 3 { return "Orchestrating \(snapshot.subagentCount) agents" }
        if snapshot.tokenMin > 800 { return "Forging" }
        if snapshot.cacheHit > 0.95 { return "Flowing" }
        if snapshot.errorRate > 0.10 { return "Struggling" }
        if snapshot.tokenMin > 200 { return "Working" }
        if snapshot.tokenMin > 50 { return "Thinking" }
        return "Idle"
    }

    private var modelIsKnown: Bool {
        let m = snapshot.model.lowercased()
        return !m.isEmpty && m != "unknown"
    }

    private var displayName: String {
        pillar.name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isAgentActive ? 6 : 4) {
            cardIdentity
            if isAgentActive {
                cardActivity
                cardVitals
            }
            cardActionBar
        }
        .padding(isAgentActive ? 12 : 10)
        .background(cardBackground)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Identity (who is this agent?)

    private var cardIdentity: some View {
        HStack(spacing: 8) {
            // Living indicator
            if snapshot.egiState > .dormant {
                EGIGlyphView(state: snapshot.egiState, size: 14)
            } else {
                BreathingDot(color: mood.color, isActive: isAgentActive)
            }

            // Name
            Text(displayName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(pillar.color)
                .lineLimit(1)

            // Inline status when idle
            if !isAgentActive {
                Text(statusVerb)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray)
            }

            // Git branch (active only)
            if isAgentActive, let branch = gitBranch {
                Text(branch)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Health score — always visible
            Text("\(snapshot.health)")
                .font(.system(size: isAgentActive ? 20 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(healthColor(for: snapshot.health))

            // Context % (only if critical)
            if snapshot.contextPercent > 0.6 {
                Text(String(format: "%.0f%%", snapshot.contextPercent * 100))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(contextColor(for: snapshot.contextPercent))
            }

            // Model badge (only if known)
            if modelIsKnown {
                Text(modelShortName(snapshot.model))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(modelColor(snapshot.model))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(modelColor(snapshot.model).opacity(0.12)))
            }
        }
    }

    // MARK: - Activity (what is the agent doing RIGHT NOW?)

    private var cardActivity: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status verb — the story
            Text(statusVerb)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#00d4aa"))

            // Current tool — what specifically
            if let toolName = snapshot.lastToolName {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7))
                        .foregroundColor(Color(hex: "#00d4aa"))

                    let display = toolDisplay(toolName, target: snapshot.lastToolTarget)
                    Text(display)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "#00d4aa").opacity(0.06))
        )
    }

    // MARK: - Vitals (health at a glance — only when active)

    private var cardVitals: some View {
        HStack(spacing: 10) {
            vital(String(format: "%.0f", snapshot.tokenMin), icon: "speedometer", color: .primary)
            vital(String(format: "€%.2f", snapshot.costEUR), icon: "eurosign.circle", color: .primary)

            Spacer()

            // Badges (subagents, errors)
            if snapshot.subagentCount > 0 {
                badge("\(snapshot.subagentCount)", icon: "person.2.fill", color: Color(hex: "#4A9EFF"))
            }
            if snapshot.errorRate > 0.01 {
                badge(String(format: "%.0f%%", snapshot.errorRate * 100), icon: "exclamationmark.triangle.fill", color: Color(hex: "#FF4444"))
            }

            Text(formatUptime(snapshot.startTime))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Action Bar (compact inline)

    private var cardActionBar: some View {
        HStack(spacing: 6) {
            Button(action: { openTerminal() }) {
                HStack(spacing: 3) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 8))
                    Text("Open")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(pillar.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(pillar.color.opacity(0.1)))
            }
            .buttonStyle(.borderless)
            .disabled(cwd == nil)

            if onKill != nil {
                Button(action: { showKillConfirm = true }) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Quit")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.red.opacity(0.06)))
                }
                .buttonStyle(.borderless)
                .alert("Stop Agent?", isPresented: $showKillConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Stop", role: .destructive) { onKill?() }
                } message: {
                    Text("This will terminate the Claude Code process.")
                }
            }

            Spacer()

            // Uptime (idle only — active shows it in vitals)
            if !isAgentActive {
                Text(formatUptime(snapshot.startTime))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    // MARK: - Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(isExpanded ? 0.08 : 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isAgentActive ? pillar.color.opacity(0.3) :
                        isExpanded ? pillar.color.opacity(0.4) :
                        pillar.color.opacity(0.1),
                        lineWidth: isAgentActive ? 1.5 : 1
                    )
            )
    }

    // MARK: - Helpers

    private func vital(_ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func badge(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(text)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
    }

    /// Makes tool output human-friendly: "Read → config.swift" instead of "Read: config.swift"
    private func toolDisplay(_ tool: String, target: String?) -> String {
        guard let t = target else { return tool }
        return "\(tool) \u{2192} \(t)"
    }

    private func openTerminal() {
        guard let dir = cwd else { return }
        TerminalOpener.open(cwd: dir)
    }
}

// MARK: - Agent Detail Panel

struct AgentDetailPanel: View {
    let snapshot: MetricsSnapshot
    let cwd: String?

    private var pillar: PillarInfo { PillarInfo.from(cwd: cwd, inferredProject: snapshot.inferredProject) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader
            panelStats
            panelContext
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(pillar.color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Circle().fill(pillar.color).frame(width: 6, height: 6)
            Text(pillar.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(pillar.color)
            Text(modelShortName(snapshot.model))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(modelColor(snapshot.model))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(modelColor(snapshot.model).opacity(0.12)))
            Spacer()

            Button(action: { openTerminal() }) {
                Label("Open", systemImage: "terminal.fill")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(pillar.color)
            }
            .buttonStyle(.borderless)
        }
    }

    private var panelStats: some View {
        HStack(spacing: 0) {
            detailStat("Speed", String(format: "%.0f t/m", snapshot.tokenMin), color: .primary)
            detailStat("Cache", String(format: "%.0f%%", snapshot.cacheHit * 100), color: snapshot.cacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
            detailStat("Errors", String(format: "%.1f%%", snapshot.errorRate * 100), color: snapshot.errorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
            detailStat("Cost", String(format: "€%.2f", snapshot.costEUR), color: .primary)
            if snapshot.subagentCount > 0 {
                detailStat("Agents", "\(snapshot.subagentCount)", color: Color(hex: "#4A9EFF"))
            }
            if let ratio = snapshot.thinkOutputRatio {
                detailStat("Think", String(format: "%.0f%%", ratio * 100), color: ratio > 0.5 ? Color(hex: "#FFA500") : Color(hex: "#00d4aa"))
            }
            detailStat("Idle", String(format: "%.0fs", snapshot.idleAvgS), color: snapshot.idleAvgS > 15 ? Color(hex: "#FFA500") : .primary)
        }
    }

    private var panelContext: some View {
        HStack(spacing: 12) {
            if snapshot.egiState > .dormant {
                EGIStateLabel(state: snapshot.egiState, confidence: snapshot.egiConfidence)
            }
            if snapshot.lastContextTokens > 0 {
                HStack(spacing: 3) {
                    Text(formatTokenCount(snapshot.lastContextTokens))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(contextColor(for: snapshot.contextPercent))
                    Text("context")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            if let anomaly = snapshot.anomaly {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color(hex: "#FFA500"))
                    Text(anomaly.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FFA500"))
                }
            }
            if snapshot.toolDiversity > 0 {
                HStack(spacing: 3) {
                    Text("\(snapshot.toolDiversity) tools")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color(hex: "#4A9EFF"))
                    Text("\(snapshot.domainSpread) domains")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(snapshot.domainSpread >= 3 ? Color(hex: "#FFD700") : Color.gray)
                }
            }
            Spacer()
        }
    }

    private func detailStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.0fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    private func openTerminal() {
        guard let dir = cwd else { return }
        TerminalOpener.open(cwd: dir)
    }
}
