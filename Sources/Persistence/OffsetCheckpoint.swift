import Foundation

enum OffsetCheckpoint {

    static func load() -> [String: OffsetEntry] {
        let url = InkPulseDefaults.offsetsFile
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let offsets = try? decoder.decode([String: OffsetEntry].self, from: data) else { return [:] }
        return offsets
    }

    static func save(_ offsets: [String: OffsetEntry]) {
        let url = InkPulseDefaults.offsetsFile
        ensureDirectory(url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(offsets) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
