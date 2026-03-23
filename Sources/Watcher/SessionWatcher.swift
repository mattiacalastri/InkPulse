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

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for dir in projectDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let key = file.path
                if tailers[key] == nil {
                    tailers[key] = FileTailer(fileURL: file)
                }
            }
        }
    }

    // MARK: - Read

    func readAll() {
        var allEvents: [ClaudeEvent] = []

        for (_, tailer) in tailers {
            let lines = tailer.readNewLines()
            for line in lines {
                let event = JSONLParser.parse(line: line)
                if case .unknown = event { continue }
                allEvents.append(event)
            }
        }

        if !allEvents.isEmpty {
            onNewEvents(allEvents)
        }
    }
}
