import Foundation

/// Manages multiple FileTailers, scanning for active JSONL files and delivering parsed events.
final class SessionWatcher {

    private let projectsDir: URL
    private let onNewEvents: ([ClaudeEvent]) -> Void

    private var tailers: [String: FileTailer] = [:]  // keyed by file path
    private var timer: Timer?

    init(projectsDir: URL, onNewEvents: @escaping ([ClaudeEvent]) -> Void) {
        self.projectsDir = projectsDir
        self.onNewEvents = onNewEvents
    }

    // MARK: - Lifecycle

    func start() {
        scanForActiveJSONL()
        readAll()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Offset Restore

    func restoreOffsets(_ offsets: [String: OffsetEntry]) {
        for (key, entry) in offsets {
            let url = URL(fileURLWithPath: entry.file)
            if FileManager.default.fileExists(atPath: url.path) {
                tailers[key] = FileTailer(fileURL: url, offset: entry.offset)
            }
        }
    }

    // MARK: - Current Offsets

    var currentOffsets: [String: OffsetEntry] {
        var result: [String: OffsetEntry] = [:]
        for (key, tailer) in tailers {
            result[key] = OffsetEntry(
                file: tailer.fileURL.path,
                offset: tailer.offset,
                lastTs: nil
            )
        }
        return result
    }

    // MARK: - Polling

    func poll() {
        scanForActiveJSONL()
        readAll()
    }

    // MARK: - Scan

    func scanForActiveJSONL() {
        let fm = FileManager.default

        // Use Process to find recently modified JSONL files efficiently
        // This avoids iterating 1000+ files with attributesOfItem
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        proc.arguments = [projectsDir.path, "-name", "*.jsonl", "-mmin", "-10", "-maxdepth", "2"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            AppState.log("find failed: \(error)")
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }

        let paths = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        AppState.log("scanForActiveJSONL: \(paths.count) recent jsonl files")

        for path in paths {
            if tailers[path] != nil { continue }
            let url = URL(fileURLWithPath: path)
            let fileSize = (try? fm.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            let tailOffset = fileSize > 500_000 ? fileSize - 500_000 : 0
            tailers[path] = FileTailer(fileURL: url, offset: tailOffset)
            AppState.log("Tracking: \(url.lastPathComponent) (size=\(fileSize), offset=\(tailOffset))")
        }
    }

    // MARK: - Read

    func readAll() {
        var allEvents: [ClaudeEvent] = []

        for (path, tailer) in tailers {
            let lines = tailer.readNewLines()
            if !lines.isEmpty {
                AppState.log("readAll: \(URL(fileURLWithPath: path).lastPathComponent) → \(lines.count) new lines")
            }
            for line in lines {
                let event = JSONLParser.parse(line: line)
                if case .unknown = event { continue }
                allEvents.append(event)
            }
        }

        if !allEvents.isEmpty {
            AppState.log("readAll: \(allEvents.count) events ingested")
            onNewEvents(allEvents)
        }
    }
}
