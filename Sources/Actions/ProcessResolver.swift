import Foundation

/// Resolves the PID of a Claude Code process by matching its cwd.
enum ProcessResolver {

    /// Finds the PID of a `claude` process whose cwd matches the given directory.
    /// Uses pgrep to find claude processes, then lsof to verify cwd.
    /// Returns nil if no match is found.
    static func findPID(for cwd: String?) -> pid_t? {
        guard let cwd = cwd, !cwd.isEmpty else { return nil }

        // Step 1: Find all claude process PIDs via pgrep
        guard let pgrepOutput = runProcess("/usr/bin/pgrep", arguments: ["-f", "claude"]) else {
            return nil
        }

        let pids = pgrepOutput
            .components(separatedBy: .newlines)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }

        guard !pids.isEmpty else { return nil }

        // Step 2: For each candidate, check cwd via lsof
        for pid in pids {
            guard let lsofOutput = runProcess("/usr/sbin/lsof", arguments: ["-p", "\(pid)", "-Fn"]) else {
                continue
            }
            // lsof -Fn outputs: "fcwd\nn<path>" — look for our cwd
            if lsofOutput.contains(cwd) {
                return pid
            }
        }

        return nil
    }

    // MARK: - Private

    private static func runProcess(_ path: String, arguments: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
