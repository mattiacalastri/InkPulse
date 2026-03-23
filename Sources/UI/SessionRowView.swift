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

// MARK: - SessionRowView

struct SessionRowView: View {
    let snapshot: MetricsSnapshot

    var body: some View {
        HStack(spacing: 8) {
            // Health color dot
            Circle()
                .fill(healthColor(for: snapshot.health))
                .frame(width: 8, height: 8)

            // Session ID (first 8 chars)
            let shortId = String(snapshot.sessionId.prefix(8)) + "..."
            Text(shortId)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)

            // Model short name (strip "claude-")
            let shortModel = snapshot.model.replacingOccurrences(of: "claude-", with: "")
            Text(shortModel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            // Duration in minutes
            let durationMin = snapshot.lastEventTime.timeIntervalSince(snapshot.startTime) / 60.0
            Text("\(Int(durationMin))m")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Cost EUR
            Text(String(format: "€%.2f", snapshot.costEUR))
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Health score number
            Text("\(snapshot.health)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(healthColor(for: snapshot.health))
        }
    }
}
