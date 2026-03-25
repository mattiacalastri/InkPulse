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
    let shortName: String

    static let home = PillarInfo(name: "Home", color: Color(hex: "#4A9EFF"), shortName: "~")

    /// Derives project identity from the working directory path.
    /// Uses the last path component with intelligent capitalization.
    static func from(cwd: String?) -> PillarInfo {
        guard let cwd = cwd else { return .home }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd == home || URL(fileURLWithPath: cwd).lastPathComponent == NSUserName() { return .home }
        let last = URL(fileURLWithPath: cwd).lastPathComponent
        let capitalized = last.prefix(1).uppercased() + last.dropFirst()
        return PillarInfo(name: capitalized, color: Color(hex: "#4A9EFF"), shortName: String(last.prefix(2).uppercased()))
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

func modelShortName(_ model: String) -> String {
    let lower = model.lowercased()
    if lower.contains("opus") { return "opus" }
    if lower.contains("sonnet") { return "sonnet" }
    if lower.contains("haiku") { return "haiku" }
    // Fallback: first word, max 8 chars
    return String(model.split(separator: "-").first ?? Substring(model)).prefix(8).lowercased()
}

func modelColor(_ model: String) -> Color {
    let lower = model.lowercased()
    if lower.contains("opus") { return Color(hex: "#00d4aa") }
    if lower.contains("sonnet") { return Color(hex: "#4A9EFF") }
    if lower.contains("haiku") { return Color(hex: "#8E8E93") }
    return Color(hex: "#FFA500")
}

func formatUptime(_ start: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(start))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    return "\(hours)h \(minutes % 60)m"
}

