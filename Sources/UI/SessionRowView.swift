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

// MARK: - Agent Mood

/// Derives an emoji mood from the snapshot metrics. Pure function, no new state.
func agentMood(for snap: MetricsSnapshot) -> (emoji: String, status: String) {
    let idle = Date().timeIntervalSince(snap.lastEventTime)

    // Sleeping — no events for >2 min
    if idle > 120 {
        return ("😴", "sleeping")
    }

    // Stalled — idle >30s
    if idle > 30 || snap.idleAvgS > 30 {
        return ("🧊", "stalled")
    }

    // Anomaly states
    if let anomaly = snap.anomaly {
        switch anomaly {
        case "loop": return ("🔄", "looping")
        case "stall": return ("🧊", "stalled")
        case "hemorrhage": return ("💸", "burning tokens")
        case "explosion": return ("🐙", "spawning \(snap.subagentCount) agents")
        case "deep_thinking": return ("🧠", "thinking deeply")
        default: break
        }
    }

    // Spawning many agents
    if snap.subagentCount > 3 {
        return ("🐙", "orchestrating \(snap.subagentCount) agents")
    }

    // High speed
    if snap.tokenMin > 800 && snap.errorRate < 0.05 {
        return ("⚡", "forging fast")
    }

    // High cache efficiency
    if snap.cacheHit > 0.95 {
        return ("🦊", "efficient")
    }

    // Struggling
    if snap.errorRate > 0.10 {
        return ("😤", "struggling")
    }

    // Normal active
    if snap.tokenMin > 200 {
        return ("🔥", "working")
    }

    // Low activity
    return ("💭", "idle")
}

// MARK: - Project Name

/// Derives a readable name from the cwd (working directory) or file path.
/// Priority: cwd last component → file path project dir → sessionId prefix
func projectName(from sessionId: String, filePath: String?, cwd: String?) -> String {
    // Best: use cwd last path component
    if let cwd = cwd {
        let last = URL(fileURLWithPath: cwd).lastPathComponent
        // Map home dir to "Home"
        if last == NSUserName() || cwd == FileManager.default.homeDirectoryForCurrentUser.path {
            return "Home"
        }
        return last
    }

    // Fallback: derive from file path
    guard let path = filePath else {
        return String(sessionId.prefix(8))
    }
    let components = path.components(separatedBy: "/")
    if let idx = components.firstIndex(of: "projects"), idx + 1 < components.count {
        let projectDir = components[idx + 1]
        let parts = projectDir.components(separatedBy: "-")
        if parts.count > 3 {
            return Array(parts.dropFirst(3)).joined(separator: "-")
        } else {
            return "Home"
        }
    }
    return String(sessionId.prefix(8))
}

// MARK: - SessionRowView

struct SessionRowView: View {
    let snapshot: MetricsSnapshot
    let filePath: String?
    let cwd: String?

    var body: some View {
        let mood = agentMood(for: snapshot)
        let name = projectName(from: snapshot.sessionId, filePath: filePath, cwd: cwd)

        HStack(spacing: 8) {
            // Emoji mood
            Text(mood.emoji)
                .font(.title3)

            // Name + status
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(mood.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Health bar + score
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(snapshot.health)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(healthColor(for: snapshot.health))

                // Mini health bar
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
        .padding(.vertical, 3)
    }
}
