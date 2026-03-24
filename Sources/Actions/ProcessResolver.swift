import Foundation

/// Resolves the PID of a Claude Code process by matching its cwd.
enum ProcessResolver {

    /// Finds the PID of a `claude` process whose cwd matches the given directory.
    /// Returns nil if no match is found.
    static func findPID(for cwd: String?) -> pid_t? {
        guard let cwd = cwd, !cwd.isEmpty else { return nil }

        // Step 1: Find all processes ending with "claude"
        guard let psOutput = runProcess("/bin/ps", arguments: ["-eo", "pid,command"]) else {
            return nil
        }

        var candidatePIDs: [pid_t] = []
        for line in psOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match lines where command ends with "claude" or contains "claude" as the main process
            if trimmed.hasSuffix("claude") || trimmed.contains("/claude ") || trimmed.contains("claude --") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let pidStr = parts.first, let pid = pid_t(pidStr) {
                    candidatePIDs.append(pid)
                }
            }
        }

        // Step 2: For each candidate, check cwd via lsof
        for pid in candidatePIDs {
            guard let lsofOutput = runProcess("/usr/sbin/lsof", arguments: ["-p", "\(pid)"]) else {
                continue
            }
            for line in lsofOutput.components(separatedBy: .newlines) {
                if line.contains("cwd") && line.contains(cwd) {
                    return pid
                }
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
