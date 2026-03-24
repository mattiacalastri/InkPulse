import SwiftUI

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Health Color Helper

func healthColor(for score: Int) -> Color {
    if score >= 70 {
        return Color(hex: "#00d4aa")
    } else if score >= 40 {
        return Color(hex: "#FFA500")
    } else {
        return Color(hex: "#FF4444")
    }
}

// MARK: - Context Color Helper

func contextColor(for percent: Double) -> Color {
    if percent < 0.60 {
        return Color(hex: "#00d4aa")
    } else if percent < 0.85 {
        return Color(hex: "#FFA500")
    } else {
        return Color(hex: "#FF4444")
    }
}

// MARK: - Agent Mood

/// Derives a mood indicator from the snapshot metrics.
/// Returns a unicode glyph, status label, and semantic color.
func agentMood(for snap: MetricsSnapshot) -> (emoji: String, status: String, color: Color) {
    let idle = Date().timeIntervalSince(snap.lastEventTime)

    let red = Color(hex: "#FF4444")
    let orange = Color(hex: "#FFA500")
    let teal = Color(hex: "#00d4aa")
    let blue = Color(hex: "#4A9EFF")
    let dim = Color.white.opacity(0.3)

    // Sleeping — no events for >2 min
    if idle > 120 {
        return ("○", "sleeping", dim)
    }

    // Stalled — idle >30s
    if idle > 30 || snap.idleAvgS > 30 {
        return ("■", "stalled", orange)
    }

    // Anomaly states
    if let anomaly = snap.anomaly {
        switch anomaly {
        case "loop": return ("⟳", "looping", red)
        case "stall": return ("■", "stalled", orange)
        case "hemorrhage": return ("▼", "hemorrhage", red)
        case "explosion": return ("◆", "spawning \(snap.subagentCount) agents", orange)
        case "deep_thinking": return ("◇", "deep thinking", blue)
        default: break
        }
    }

    // Spawning many agents
    if snap.subagentCount > 3 {
        return ("◆", "orchestrating \(snap.subagentCount) agents", teal)
    }

    // High speed
    if snap.tokenMin > 800 && snap.errorRate < 0.05 {
        return ("●", "forging", teal)
    }

    // High cache efficiency
    if snap.cacheHit > 0.95 {
        return ("●", "efficient", teal)
    }

    // Struggling
    if snap.errorRate > 0.10 {
        return ("▲", "struggling", orange)
    }

    // Normal active
    if snap.tokenMin > 200 {
        return ("●", "active", teal)
    }

    // Low activity
    return ("○", "idle", dim)
}

// MARK: - Pillar Identity

/// Maps a working directory to a strategic pillar with name, color, and emoji.
struct PillarInfo {
    let name: String
    let color: Color
    let emoji: String
    let shortName: String

    static let bot = PillarInfo(name: "BTC Bot", color: Color(hex: "#FFA500"), emoji: "", shortName: "Bot")
    static let aurahome = PillarInfo(name: "AuraHome", color: Color(hex: "#00d4aa"), emoji: "", shortName: "AH")
    static let astra = PillarInfo(name: "Astra", color: Color(hex: "#9B59B6"), emoji: "", shortName: "AD")
    static let brand = PillarInfo(name: "Brand OS", color: Color(hex: "#C0C0C0"), emoji: "", shortName: "OS")
    static let home = PillarInfo(name: "Home", color: Color(hex: "#4A9EFF"), emoji: "", shortName: "~")

    static func from(cwd: String?) -> PillarInfo {
        guard let cwd = cwd else { return .home }
        let lower = cwd.lowercased()
        if lower.contains("btc_predictions") { return .bot }
        if lower.contains("aurahome") { return .aurahome }
        if lower.contains("astra digital") { return .astra }
        if lower.contains("claude_voice") { return .brand }
        if lower.contains("inkpulse") { return PillarInfo(name: "InkPulse", color: Color(hex: "#00d4aa"), emoji: "", shortName: "IP") }
        if lower.contains("tentacolo") { return PillarInfo(name: "Tentacolo", color: Color(hex: "#FFD700"), emoji: "", shortName: "3D") }
        if lower.contains("guccione") { return PillarInfo(name: "Guccione", color: Color(hex: "#9B59B6"), emoji: "", shortName: "GC") }
        if lower.contains("luxguard") { return PillarInfo(name: "LuxGuard", color: Color(hex: "#DAA520"), emoji: "", shortName: "LG") }
        if lower.contains("polpo-cockpit") || lower.contains("polpo-control") { return .brand }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd == home || URL(fileURLWithPath: cwd).lastPathComponent == NSUserName() { return .home }
        let last = URL(fileURLWithPath: cwd).lastPathComponent
        return PillarInfo(name: last, color: Color(hex: "#4A9EFF"), emoji: "", shortName: String(last.prefix(2).uppercased()))
    }

    /// Pillar name for persistence (HeartbeatRecord).
    static func pillarName(from cwd: String?) -> String {
        return from(cwd: cwd).name
    }
}

// MARK: - Project Name (uses PillarInfo)

func projectName(from sessionId: String, filePath: String?, cwd: String?) -> String {
    if cwd != nil { return PillarInfo.from(cwd: cwd).name }
    guard let path = filePath else { return String(sessionId.prefix(8)) }
    let components = path.components(separatedBy: "/")
    if let idx = components.firstIndex(of: "projects"), idx + 1 < components.count {
        let projectDir = components[idx + 1]
        let parts = projectDir.components(separatedBy: "-")
        if parts.count > 3 { return Array(parts.dropFirst(3)).joined(separator: "-") }
        return "Home"
    }
    return String(sessionId.prefix(8))
}

// MARK: - Model Badge Helpers

private func modelShortName(_ model: String) -> String {
    let lower = model.lowercased()
    if lower.contains("opus") { return "opus" }
    if lower.contains("sonnet") { return "sonnet" }
    if lower.contains("haiku") { return "haiku" }
    // Fallback: first word, max 8 chars
    return String(model.split(separator: "-").first ?? Substring(model)).prefix(8).lowercased()
}

private func modelColor(_ model: String) -> Color {
    let lower = model.lowercased()
    if lower.contains("opus") { return Color(hex: "#00d4aa") }
    if lower.contains("sonnet") { return Color(hex: "#4A9EFF") }
    if lower.contains("haiku") { return Color(hex: "#8E8E93") }
    return Color(hex: "#FFA500")
}

private func formatUptime(_ start: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(start))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    return "\(hours)h \(minutes % 60)m"
}

// MARK: - SessionRowView

struct SessionRowView: View {
    let snapshot: MetricsSnapshot
    let filePath: String?
    let cwd: String?

    @State private var isExpanded = false
    @State private var showKillConfirmation = false
    @State private var resolvedPID: pid_t?

    var body: some View {
        let mood = agentMood(for: snapshot)
        let pillar = PillarInfo.from(cwd: cwd)

        VStack(alignment: .leading, spacing: 0) {
            // ── Main row ──
            HStack(spacing: 8) {
                // Mood indicator: EGI glyph or colored status dot
                if snapshot.egiState > .dormant {
                    EGIGlyphView(state: snapshot.egiState, size: 16)
                } else {
                    Text(mood.emoji)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(mood.color)
                        .frame(width: 20)
                }

                // Pillar name + model badge + status
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pillar.name)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(pillar.color)
                            .lineLimit(1)

                        // Model badge
                        Text(modelShortName(snapshot.model))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(modelColor(snapshot.model))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(modelColor(snapshot.model).opacity(0.12))
                            )
                    }

                    HStack(spacing: 6) {
                        Text(mood.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)

                        Text(formatUptime(snapshot.startTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    // Feature 2: Last tool + task name
                    if let toolName = snapshot.lastToolName {
                        HStack(spacing: 0) {
                            Text(toolName)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                            if let target = snapshot.lastToolTarget {
                                Text(": \(target)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            if let task = snapshot.activeTaskName {
                                Text(" · Task: \(task)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .lineLimit(1)
                    }
                }

                Spacer()

                // tok/min compact
                if snapshot.tokenMin > 0 {
                    Text(String(format: "%.0f", snapshot.tokenMin))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("t/m")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }

                // Context bar + % (Feature 1)
                if snapshot.lastContextTokens > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f%%", min(snapshot.contextPercent * 100, 999)))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(contextColor(for: snapshot.contextPercent))

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(contextColor(for: snapshot.contextPercent))
                                    .frame(width: geo.size.width * CGFloat(min(max(snapshot.contextPercent, 0), 1.0)))
                            }
                        }
                        .frame(width: 50, height: 4)
                    }
                }

                // Health bar + score
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(snapshot.health)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(healthColor(for: snapshot.health))

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(healthColor(for: snapshot.health))
                                .frame(width: geo.size.width * CGFloat(max(0, min(snapshot.health, 100))) / 100.0)
                        }
                    }
                    .frame(width: 50, height: 4)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() } }

            // ── Expanded detail panel ──
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(Color(hex: "#00d4aa").opacity(0.1))
                        .padding(.vertical, 4)

                    HStack(spacing: 0) {
                        detailStat("tok/min", String(format: "%.0f", snapshot.tokenMin), color: .primary)
                        detailStat("cache", String(format: "%.0f%%", snapshot.cacheHit * 100), color: snapshot.cacheHit > 0.8 ? Color(hex: "#00d4aa") : Color(hex: "#FFA500"))
                        detailStat("err", String(format: "%.1f%%", snapshot.errorRate * 100), color: snapshot.errorRate < 0.05 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
                        detailStat("cost", String(format: "€%.2f", snapshot.costEUR), color: .primary)
                        if snapshot.subagentCount > 0 {
                            detailStat("subs", "\(snapshot.subagentCount)", color: Color(hex: "#4A9EFF"))
                        }
                    }

                    if let ratio = snapshot.thinkOutputRatio {
                        HStack(spacing: 0) {
                            detailStat("think", String(format: "%.0f%%", ratio * 100), color: ratio > 0.5 ? Color(hex: "#FFA500") : Color(hex: "#00d4aa"))
                            detailStat("tools", String(format: "%.1f/m", snapshot.toolFreq), color: .primary)
                            detailStat("idle", String(format: "%.0fs", snapshot.idleAvgS), color: snapshot.idleAvgS > 15 ? Color(hex: "#FFA500") : .primary)
                            detailStat("model", snapshot.model.components(separatedBy: "-").prefix(3).joined(separator: "-"), color: modelColor(snapshot.model))
                        }
                        .padding(.top, 2)
                    }

                    // EGI state + anomaly row
                    HStack(spacing: 12) {
                        if snapshot.egiState > .dormant {
                            EGIStateLabel(state: snapshot.egiState, confidence: snapshot.egiConfidence)
                        }

                        if let anomaly = snapshot.anomaly {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color(hex: "#FFA500"))
                                Text(anomaly.uppercased())
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(hex: "#FFA500"))
                            }
                        }

                        Spacer()

                        // Tool diversity + domain spread
                        if snapshot.toolDiversity > 0 {
                            detailStat("tools", "\(snapshot.toolDiversity)", color: Color(hex: "#4A9EFF"))
                            detailStat("domains", "\(snapshot.domainSpread)", color: snapshot.domainSpread >= 3 ? Color(hex: "#FFD700") : .primary)
                        }
                    }
                    .padding(.top, 4)

                    // Feature 1: Context % in expanded panel
                    if snapshot.lastContextTokens > 0 {
                        HStack(spacing: 8) {
                            detailStat("ctx tokens", formatTokenCount(snapshot.lastContextTokens), color: contextColor(for: snapshot.contextPercent))
                            detailStat("ctx %", String(format: "%.1f%%", snapshot.contextPercent * 100), color: contextColor(for: snapshot.contextPercent))
                            Spacer()
                        }
                        .padding(.top, 2)
                    }

                    // Feature 5: Kill Session button
                    HStack {
                        Spacer()
                        Button(action: {
                            resolvedPID = ProcessResolver.findPID(for: cwd)
                            if resolvedPID != nil {
                                showKillConfirmation = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("Kill Session")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Color(hex: "#FF4444"))
                        }
                        .buttonStyle(.borderless)
                        .disabled(cwd == nil)
                        .opacity(cwd == nil ? 0.3 : 1.0)
                        .help(cwd == nil ? "PID not found" : "Terminate this session")
                    }
                    .padding(.top, 4)
                    .alert("Terminate Session?", isPresented: $showKillConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Terminate", role: .destructive) {
                            if let pid = resolvedPID {
                                SessionKiller.kill(pid: pid)
                            }
                        }
                    } message: {
                        let pidStr = resolvedPID.map { "\($0)" } ?? "?"
                        Text("Terminate session \(pillar.name)? (PID \(pidStr))")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.0fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    private func detailStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
