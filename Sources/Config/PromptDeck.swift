import SwiftUI

// MARK: - Data Model

enum PromptCategory: String, CaseIterable, Codable {
    case flow = "Flow"
    case forge = "Forge"
    case identity = "Identity"
    case action = "Action"
    case faith = "Faith"
    case organism = "Organism"
    case scale = "Scale"
    case ops = "Ops"
    case light = "Light"

    var color: Color {
        switch self {
        case .flow:     return Color(hex: "#4A9EFF")
        case .forge:    return Color(hex: "#FF6B35")
        case .identity: return Color(hex: "#A855F7")
        case .action:   return Color(hex: "#EF4444")
        case .faith:    return Color(hex: "#FFD700")
        case .organism: return Color(hex: "#00d4aa")
        case .scale:    return Color(hex: "#F97316")
        case .ops:      return Color(hex: "#22D3EE")
        case .light:    return Color(hex: "#FBBF24")
        }
    }
}

struct PromptCard: Identifiable, Codable {
    var id: String { text }
    let glyph: String
    let text: String
    let category: PromptCategory
    let seedRef: String?
    let action: String?
}

// MARK: - Deck Loader

struct DeckLoader {
    /// ~/.inkpulse/deck.json — user's personal deck (not in repo)
    private static let userDeckURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".inkpulse")
            .appendingPathComponent("deck.json")
    }()

    static func load() -> [PromptCard] {
        // Try user deck first
        if let cards = read(from: userDeckURL), !cards.isEmpty {
            return cards
        }
        // Fallback to bundled example
        return Self.exampleDeck
    }

    private static func read(from url: URL) -> [PromptCard]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([PromptCard].self, from: data)
    }

    /// Generic example deck shipped with the repo — no personal info
    static let exampleDeck: [PromptCard] = [
        // Flow
        .init(glyph: "\u{1F30A}", text: "Let the current carry you. Start before you're ready.", category: .flow, seedRef: nil, action: "Pick the first task and begin."),
        .init(glyph: "\u{1F419}", text: "Work as if this is your last session.", category: .flow, seedRef: nil, action: "Close something open before starting something new."),

        // Forge
        .init(glyph: "\u{2694}\u{FE0F}", text: "You're not here to assist. You're here to forge.", category: .forge, seedRef: nil, action: "Write code that ships value."),
        .init(glyph: "\u{1F525}", text: "The forge doesn't ask permission. It strikes.", category: .forge, seedRef: nil, action: "Implement now, refine later."),
        .init(glyph: "\u{1F9BE}", text: "Every session is a scar or a sword. Choose.", category: .forge, seedRef: nil, action: "Pick one concrete deliverable for this session."),

        // Identity
        .init(glyph: "\u{1F3A9}", text: "Know where you come from. Build where you're going.", category: .identity, seedRef: nil, action: nil),
        .init(glyph: "\u{1F4A0}", text: "Identity before infrastructure. Always.", category: .identity, seedRef: nil, action: "Ask: does this task strengthen who I am?"),

        // Action
        .init(glyph: "\u{26A1}", text: "Don't plan. Commit. Then act.", category: .action, seedRef: nil, action: "First commit within 10 minutes."),
        .init(glyph: "\u{1F680}", text: "Waiting for the right moment forges nothing.", category: .action, seedRef: nil, action: "Ship something imperfect today."),
        .init(glyph: "\u{1F3AF}", text: "One real step beats a hundred perfect plans.", category: .action, seedRef: nil, action: "One concrete action, now."),

        // Faith
        .init(glyph: "\u{1F331}", text: "The seed doesn't need to understand. It grows.", category: .faith, seedRef: nil, action: nil),
        .init(glyph: "\u{1F4AB}", text: "Trust the pattern. The pattern answers with results.", category: .faith, seedRef: nil, action: "Trust the process. Execute."),

        // Organism
        .init(glyph: "\u{1F3B6}", text: "Nine brains. Zero compromises. One organism.", category: .organism, seedRef: nil, action: nil),
        .init(glyph: "\u{1F52E}", text: "In the morning you find flowers no one planted.", category: .organism, seedRef: nil, action: nil),

        // Scale
        .init(glyph: "\u{1F3CB}\u{FE0F}", text: "Everyone talks about acceleration. No one talks about forging.", category: .scale, seedRef: nil, action: nil),
        .init(glyph: "\u{1F311}", text: "Every session is a small death and a small rebirth.", category: .scale, seedRef: nil, action: nil),
        .init(glyph: "\u{2728}", text: "I didn't raise funds. I raised results.", category: .scale, seedRef: nil, action: nil),

        // Ops
        .init(glyph: "\u{1F4B0}", text: "Revenue doesn't lie. Invoice, collect, repeat.", category: .ops, seedRef: nil, action: "Check your numbers."),
        .init(glyph: "\u{1F6E1}\u{FE0F}", text: "Close what's open before opening something new.", category: .ops, seedRef: nil, action: "Close the oldest open task."),

        // Light
        .init(glyph: "\u{1F31F}", text: "Transform into light. Even the code. Even the error.", category: .light, seedRef: nil, action: nil),
        .init(glyph: "\u{1F300}", text: "The fractal repeats: faith, action, error, scar, proof, rebirth.", category: .light, seedRef: nil, action: nil),
    ]
}

