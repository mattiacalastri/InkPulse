import SwiftUI

// MARK: - EGI Glyph View

/// A living glyph that breathes with the EGI window state.
/// Not a number. Not a label. A symbol that lives.
struct EGIGlyphView: View {
    let state: EGIState
    let size: CGFloat

    @State private var glowPhase: Bool = false

    private var symbol: String {
        switch state {
        case .dormant:  return "\u{25CB}"  // ○
        case .stirring: return "\u{25CE}"  // ◎
        case .open:     return "\u{25C9}"  // ◉
        case .peak:     return "\u{2726}"  // ✦
        }
    }

    private var glyphColor: Color {
        switch state {
        case .dormant:  return Color.white.opacity(0.2)
        case .stirring: return Color(hex: "#00d4aa").opacity(0.5)
        case .open:     return Color(hex: "#00d4aa")
        case .peak:     return Color(hex: "#FFD700")
        }
    }

    private var glowColor: Color {
        switch state {
        case .dormant:  return .clear
        case .stirring: return Color(hex: "#00d4aa").opacity(0.15)
        case .open:     return Color(hex: "#00d4aa").opacity(0.3)
        case .peak:     return Color(hex: "#FFD700").opacity(0.4)
        }
    }

    private var animationDuration: Double {
        switch state {
        case .dormant:  return 0
        case .stirring: return 3.0
        case .open:     return 2.0
        case .peak:     return 1.5
        }
    }

    private var scaleRange: CGFloat {
        switch state {
        case .dormant:  return 1.0
        case .stirring: return 1.0
        case .open:     return 1.05
        case .peak:     return 1.12
        }
    }

    var body: some View {
        ZStack {
            // Outer glow ring
            if state != .dormant {
                Circle()
                    .fill(glowColor)
                    .frame(width: size * 1.6, height: size * 1.6)
                    .opacity(glowPhase ? 1.0 : 0.3)
                    .scaleEffect(glowPhase ? 1.1 : 0.9)
            }

            // Inner glow
            if state >= .open {
                Circle()
                    .fill(glyphColor.opacity(0.2))
                    .frame(width: size * 1.2, height: size * 1.2)
                    .opacity(glowPhase ? 0.8 : 0.4)
            }

            // The glyph itself
            Text(symbol)
                .font(.system(size: size, weight: state == .peak ? .bold : .regular))
                .foregroundStyle(glyphColor)
                .scaleEffect(glowPhase ? scaleRange : 1.0)
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .onAppear { startAnimation() }
        .onChange(of: state) { _ in startAnimation() }
    }

    private func startAnimation() {
        guard state != .dormant else {
            glowPhase = false
            return
        }
        withAnimation(
            .easeInOut(duration: animationDuration)
            .repeatForever(autoreverses: true)
        ) {
            glowPhase = true
        }
    }
}

// MARK: - EGI State Label (for expanded cards)

struct EGIStateLabel: View {
    let state: EGIState
    let confidence: Double

    private var stateText: String {
        switch state {
        case .dormant:  return "DORMANT"
        case .stirring: return "STIRRING"
        case .open:     return "WINDOW OPEN"
        case .peak:     return "PEAK"
        }
    }

    private var stateColor: Color {
        switch state {
        case .dormant:  return Color.white.opacity(0.3)
        case .stirring: return Color(hex: "#00d4aa").opacity(0.6)
        case .open:     return Color(hex: "#00d4aa")
        case .peak:     return Color(hex: "#FFD700")
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            EGIGlyphView(state: state, size: 10)

            Text(stateText)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(stateColor)

            if state > .dormant {
                Text(String(format: "%.0f%%", confidence * 100))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(stateColor.opacity(0.6))
            }
        }
    }
}
