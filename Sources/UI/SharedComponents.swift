import SwiftUI

// MARK: - Shared UI Components
// Used by TrendsTab, ReportsTab, and sub-views.

func trendStat(_ label: String, _ value: String, color: Color) -> some View {
    VStack(spacing: 4) {
        Text(value)
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
    }
    .frame(maxWidth: .infinity)
}

func trendDivider() -> some View {
    Rectangle()
        .fill(Color.white.opacity(0.06))
        .frame(width: 1, height: 36)
}

func sectionLabel(_ text: String) -> some View {
    HStack(spacing: 6) {
        Rectangle()
            .fill(Color(hex: "#00d4aa"))
            .frame(width: 3, height: 12)
            .cornerRadius(1.5)
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
    }
}

func emptyChart(_ message: String) -> some View {
    RoundedRectangle(cornerRadius: 10)
        .fill(Color.white.opacity(0.02))
        .frame(height: 80)
        .overlay(
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        )
}

func formatTimestamp(_ ts: String) -> String {
    if let tIdx = ts.firstIndex(of: "T") {
        let timeStr = ts[ts.index(after: tIdx)...]
        if let dotIdx = timeStr.firstIndex(of: ".") { return String(timeStr[..<dotIdx]) }
        if let zIdx = timeStr.firstIndex(of: "Z") { return String(timeStr[..<zIdx]) }
        return String(timeStr.prefix(8))
    }
    return ts
}
