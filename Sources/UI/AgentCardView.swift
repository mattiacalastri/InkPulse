import SwiftUI
import AppKit

// MARK: - Pulse Modifier (living mood indicator)

struct PulseEffect: ViewModifier {
    let isActive: Bool
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color.opacity(isPulsing && isActive ? 0.6 : 0), lineWidth: 3)
                    .scaleEffect(isPulsing && isActive ? 1.8 : 1.0)
            )
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .onChange(of: isActive) { active in
                if active {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    isPulsing = false
                }
            }
    }
}

// MARK: - Agent Card View

/// Compact agent card designed for a 2-column grid.
/// Expansion is managed externally by PopoverView to avoid grid layout issues.
struct AgentCardView: View {
    let snapshot: MetricsSnapshot
    let filePath: String?
    let cwd: String?
    let gitBranch: String?
    let isExpanded: Bool
    let onTap: () -> Void

    private var mood: (emoji: String, status: String, color: Color) {
        agentMood(for: snapshot)
    }

    private var pillar: PillarInfo {
        PillarInfo.from(cwd: cwd)
    }

    /// Agent is actively working (not sleeping/stalled/idle)
    private var isAgentActive: Bool {
        let idle = Date().timeIntervalSince(snapshot.lastEventTime)
        return idle < 30 && snapshot.tokenMin > 50
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardHeader
            cardStatusLine
            cardCurrentActivity
            cardStats
            cardBars
            cardActions
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isExpanded ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isExpanded ? pillar.color.opacity(0.4) : pillar.color.opacity(0.15), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Card Sections

    private var cardHeader: some View {
        HStack(spacing: 6) {
            if snapshot.egiState > .dormant {
                EGIGlyphView(state: snapshot.egiState, size: 14)
            } else {
                Circle()
                    .fill(mood.color)
                    .frame(width: 8, height: 8)
                    .modifier(PulseEffect(isActive: isAgentActive, color: mood.color))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(pillar.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(pillar.color)
                    .lineLimit(1)

                if let branch = gitBranch {
                    Text(branch)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else if pillar.name == "Home" {
                    Text(String(snapshot.sessionId.prefix(8)))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(modelShortName(snapshot.model))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(modelColor(snapshot.model))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(modelColor(snapshot.model).opacity(0.12))
                )
        }
    }

    private var cardStatusLine: some View {
        HStack(spacing: 4) {
            Text(mood.status)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\u{00B7}")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Text(formatUptime(snapshot.startTime))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    @ViewBuilder
    private var cardCurrentActivity: some View {
        if let toolName = snapshot.lastToolName {
            HStack(spacing: 4) {
                Image(systemName: isAgentActive ? "bolt.fill" : "clock")
                    .font(.system(size: 7))
                    .foregroundColor(isAgentActive ? Color(hex: "#00d4aa") : Color.gray)
                Text(toolName)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isAgentActive ? .white : .gray)
                if let target = snapshot.lastToolTarget {
                    Text(target)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(isAgentActive ? Color.white.opacity(0.6) : Color.gray.opacity(0.5))
                }
            }
            .lineLimit(1)
        }
    }

    private var cardStats: some View {
        HStack(spacing: 0) {
            cardStat(String(format: "%.0f", snapshot.tokenMin), "t/m")
            Spacer()
            cardStat(String(format: "%.0f%%", snapshot.cacheHit * 100), "cache")
            Spacer()
            cardStat(String(format: "\u{20AC}%.2f", snapshot.costEUR), "cost")
        }
    }

    private var cardBars: some View {
        HStack(spacing: 8) {
            miniBar(value: max(0, min(snapshot.health, 100)), max: 100,
                    label: "\(snapshot.health)", color: healthColor(for: snapshot.health))

            if snapshot.lastContextTokens > 0 {
                let pct = min(snapshot.contextPercent, 1.0)
                miniBar(value: Int(pct * 100), max: 100,
                        label: String(format: "%.0f%%", min(snapshot.contextPercent * 100, 999)),
                        color: contextColor(for: snapshot.contextPercent))
            }
        }
    }

    private var cardActions: some View {
        HStack(spacing: 8) {
            Button(action: { openTerminal() }) {
                HStack(spacing: 3) {
                    Image(systemName: "terminal")
                        .font(.system(size: 8))
                    Text("Open")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(pillar.color.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .disabled(cwd == nil)

            Spacer()

            if snapshot.subagentCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 7))
                    Text("\(snapshot.subagentCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color(hex: "#4A9EFF"))
            }

            if snapshot.errorRate > 0.01 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 7))
                    Text(String(format: "%.0f%%", snapshot.errorRate * 100))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color(hex: "#FF4444"))
            }
        }
    }

    // MARK: - Components

    private func miniBar(value: Int, max: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(value) / CGFloat(max))
                }
            }
            .frame(height: 3)
        }
    }

    private func cardStat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func openTerminal() {
        guard let dir = cwd else { return }
        let script = "tell application \"Terminal\" to do script \"cd \(dir.replacingOccurrences(of: "\"", with: "\\\""))\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - Agent Detail Panel (full-width, shown below grid when a card is selected)

struct AgentDetailPanel: View {
    let snapshot: MetricsSnapshot
    let cwd: String?

    @State private var showKillConfirmation = false
    @State private var resolvedPID: pid_t?

    private var pillar: PillarInfo {
        PillarInfo.from(cwd: cwd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(pillar.color)
                    .frame(width: 6, height: 6)
                Text(pillar.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(pillar.color)
                Text(modelShortName(snapshot.model))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(modelColor(snapshot.model))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(modelColor(snapshot.model).opacity(0.12)))
                Spacer()

                // Open Terminal
                Button(action: { openTerminal() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "terminal")
                            .font(.system(size: 8))
                        Text("Open")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(pillar.color.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .disabled(cwd == nil)

                // Kill
                Button(action: {
                    resolvedPID = ProcessResolver.findPID(for: cwd)
                    if resolvedPID != nil {
                        showKillConfirmation = true
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 8))
                        Text("Kill")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(Color(hex: "#FF4444").opacity(0.5))
                }
                .buttonStyle(.borderless)
                .disabled(cwd == nil)
            }

            // Stats grid
            HStack(spacing: 0) {
                detailStat("tok/min", String(format: "%.0f", snapshot.tokenMin), color: .primary)
                detailStat("cache", String(format: "%.0f%%", snapshot.cacheHit * 100), color: snapshot.cacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
                detailStat("err", String(format: "%.1f%%", snapshot.errorRate * 100), color: snapshot.errorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
                detailStat("cost", String(format: "\u{20AC}%.2f", snapshot.costEUR), color: .primary)
                if snapshot.subagentCount > 0 {
                    detailStat("subs", "\(snapshot.subagentCount)", color: Color(hex: "#4A9EFF"))
                }
                if let ratio = snapshot.thinkOutputRatio {
                    detailStat("think", String(format: "%.0f%%", ratio * 100), color: ratio > 0.5 ? Color(hex: "#FFA500") : Color(hex: "#00d4aa"))
                }
                detailStat("idle", String(format: "%.0fs", snapshot.idleAvgS), color: snapshot.idleAvgS > 15 ? Color(hex: "#FFA500") : .primary)
                detailStat("tools", String(format: "%.1f/m", snapshot.toolFreq), color: .primary)
            }

            // EGI + Context + Anomaly row
            HStack(spacing: 12) {
                if snapshot.egiState > .dormant {
                    EGIStateLabel(state: snapshot.egiState, confidence: snapshot.egiConfidence)
                }

                if snapshot.lastContextTokens > 0 {
                    HStack(spacing: 4) {
                        Text(formatTokenCount(snapshot.lastContextTokens))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(contextColor(for: snapshot.contextPercent))
                        Text("ctx")
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
                    HStack(spacing: 4) {
                        Text("\(snapshot.toolDiversity)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#4A9EFF"))
                        Text("tools")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("\(snapshot.domainSpread)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(snapshot.domainSpread >= 3 ? Color(hex: "#FFD700") : .primary)
                        Text("domains")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(pillar.color.opacity(0.2), lineWidth: 1)
                )
        )
        .alert("Terminate Session?", isPresented: $showKillConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Terminate", role: .destructive) {
                if let pid = resolvedPID {
                    SessionKiller.kill(pid: pid)
                }
            }
        } message: {
            let pidStr = resolvedPID.map { "\($0)" } ?? "?"
            Text("Terminate \(pillar.name)? (PID \(pidStr))")
        }
    }

    // MARK: - Components

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
        let script = "tell application \"Terminal\" to do script \"cd \(dir.replacingOccurrences(of: "\"", with: "\\\""))\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
