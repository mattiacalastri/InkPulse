import Foundation

/// Reads new lines incrementally from a file, tracking the byte offset.
final class FileTailer {

    let fileURL: URL
    private(set) var offset: UInt64
    private var isFirstRead: Bool

    init(fileURL: URL, offset: UInt64 = 0) {
        self.fileURL = fileURL
        self.offset = offset
        self.isFirstRead = offset > 0 // if starting mid-file, first line is partial
    }

    /// Read all new lines appended since the last read.
    /// Returns an empty array if the file does not exist or no new data is available.
    func readNewLines() -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }

        // Seek to our saved offset
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return []
        }

        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }

        // Update offset to current position
        offset += UInt64(data.count)

        guard let text = String(data: data, encoding: .utf8) else { return [] }

        // Split by newlines, filtering out empty trailing elements
        var lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }

        // When starting mid-file, first line is always truncated — skip it
        if isFirstRead && !lines.isEmpty {
            lines.removeFirst()
            isFirstRead = false
        }

        return lines
    }
}
