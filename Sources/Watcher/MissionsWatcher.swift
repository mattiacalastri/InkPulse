import Foundation

/// Watches ~/.inkpulse/missions.json for changes using DispatchSource (FSEvents).
/// When the file is written or modified, decodes it and calls the callback.
final class MissionsWatcher {

    private let directory: URL
    private let missionsFileName = "missions.json"
    private let onMissionsReady: (MissionsFile) -> Void

    private var dirSource: DispatchSourceFileSystemObject?
    private var dirFd: Int32 = -1
    private var pollTimer: Timer?
    private var lastModDate: Date?
    private let debounceInterval: TimeInterval = 1.5

    init(directory: URL, onMissionsReady: @escaping (MissionsFile) -> Void) {
        self.directory = directory
        self.onMissionsReady = onMissionsReady
    }

    var missionsPath: URL { directory.appendingPathComponent(missionsFileName) }

    // MARK: - Lifecycle

    func start() {
        startDirectoryWatch()
        startPollTimer()
        AppState.log("MissionsWatcher started on \(directory.path)")
    }

    func stop() {
        dirSource?.cancel()
        dirSource = nil
        if dirFd >= 0 { close(dirFd) }
        dirFd = -1
        pollTimer?.invalidate()
        pollTimer = nil
        AppState.log("MissionsWatcher stopped")
    }

    // MARK: - Directory Watch (FSEvents via DispatchSource)

    private func startDirectoryWatch() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            AppState.log("MissionsWatcher: could not open directory \(directory.path)")
            return
        }
        dirFd = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.checkFile()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        dirSource = source
    }

    // MARK: - Poll Fallback

    private func startPollTimer() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFile()
        }
    }

    // MARK: - File Check (debounced)

    private func checkFile() {
        let path = missionsPath.path
        guard FileManager.default.fileExists(atPath: path) else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let modDate = attrs?[.modificationDate] as? Date else { return }

        // Debounce: only fire if file changed since last check
        if let last = lastModDate, modDate.timeIntervalSince(last) < debounceInterval {
            return
        }

        // Additional debounce: wait for file to stop changing
        let size1 = attrs?[.size] as? UInt64 ?? 0
        Thread.sleep(forTimeInterval: debounceInterval)
        let attrs2 = try? FileManager.default.attributesOfItem(atPath: path)
        let size2 = attrs2?[.size] as? UInt64 ?? 0
        guard size1 == size2, size1 > 0 else { return }

        lastModDate = modDate

        guard let data = try? Data(contentsOf: missionsPath),
              let file = try? JSONDecoder().decode(MissionsFile.self, from: data) else {
            AppState.log("MissionsWatcher: failed to decode missions.json")
            return
        }

        AppState.log("MissionsWatcher: decoded \(file.missions.count) missions")
        onMissionsReady(file)
    }

    /// Deletes missions.json to prevent stale re-reads on next launch.
    func cleanup() {
        try? FileManager.default.removeItem(at: missionsPath)
        AppState.log("MissionsWatcher: cleaned up missions.json")
    }
}
