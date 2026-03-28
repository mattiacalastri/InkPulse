import SwiftUI

/// Edit the motivational deck from the Config UI — no JSON editing needed.
struct DeckEditorView: View {
    @Binding var isPresented: Bool
    @State private var cards: [EditableCard] = []
    @State private var hasChanges = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                Spacer()
                Text("Edit Deck")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider()

            // Cards list
            List {
                ForEach($cards) { $card in
                    cardRow(card: $card)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            }
            .listStyle(.plain)

            Divider()

            // Footer
            HStack {
                Button(action: addCard) {
                    Label("Add Card", systemImage: "plus.circle.fill")
                        .font(.system(.caption, design: .rounded))
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Reset to Default") { resetToDefault() }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)

                Text("\(cards.count) cards")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .frame(width: 520, height: 480)
        .onAppear { loadDeck() }
    }

    // MARK: - Card Row

    private func cardRow(card: Binding<EditableCard>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Emoji", text: card.glyph)
                    .frame(width: 36)
                    .textFieldStyle(.roundedBorder)

                Picker("", selection: card.category) {
                    ForEach(PromptCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue.capitalized).tag(cat)
                    }
                }
                .frame(width: 90)
                .labelsHidden()
            }

            TextField("Quote text", text: card.text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .rounded))
                .onChange(of: card.wrappedValue.text) { _, _ in hasChanges = true }

            TextField("Action (optional)", text: card.action)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func loadDeck() {
        let loaded = DeckLoader.load()
        cards = loaded.map { EditableCard(from: $0) }
    }

    private func addCard() {
        cards.append(EditableCard(
            glyph: "✨", text: "New card", category: .flow, action: ""
        ))
        hasChanges = true
    }

    private func delete(at offsets: IndexSet) {
        cards.remove(atOffsets: offsets)
        hasChanges = true
    }

    private func move(from src: IndexSet, to dst: Int) {
        cards.move(fromOffsets: src, toOffset: dst)
        hasChanges = true
    }

    private func save() {
        let promptCards = cards.map { card in
            PromptCard(
                glyph: card.glyph,
                text: card.text,
                category: card.category,
                seedRef: nil,
                action: card.action.isEmpty ? nil : card.action
            )
        }
        DeckSaver.save(promptCards)
        hasChanges = false
        isPresented = false
    }

    private func resetToDefault() {
        // Delete user deck file → falls back to example deck
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".inkpulse")
            .appendingPathComponent("deck.json")
        try? FileManager.default.removeItem(at: url)
        loadDeck()
        hasChanges = false
    }
}

// MARK: - Editable Card Model

struct EditableCard: Identifiable {
    let id = UUID()
    var glyph: String
    var text: String
    var category: PromptCategory
    var action: String

    init(glyph: String, text: String, category: PromptCategory, action: String) {
        self.glyph = glyph
        self.text = text
        self.category = category
        self.action = action
    }

    init(from card: PromptCard) {
        self.glyph = card.glyph
        self.text = card.text
        self.category = card.category
        self.action = card.action ?? ""
    }
}

// MARK: - Deck Saver

struct DeckSaver {
    static func save(_ cards: [PromptCard]) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".inkpulse")
            .appendingPathComponent("deck.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(cards) {
            try? data.write(to: url)
        }
    }
}
