import Foundation

/// Terminates a Claude Code process. Sends SIGTERM first, then SIGKILL after 5 seconds if still alive.
/// NEVER call without user confirmation via .alert().
enum SessionKiller {

    /// Sends SIGTERM to the given PID, then SIGKILL after 5s if the process is still alive.
    static func kill(pid: pid_t) {
        AppState.log("SessionKiller: sending SIGTERM to PID \(pid)")
        Darwin.kill(pid, SIGTERM)

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            // Check if still alive (kill with signal 0 tests existence)
            if Darwin.kill(pid, 0) == 0 {
                AppState.log("SessionKiller: PID \(pid) still alive after 5s, sending SIGKILL")
                Darwin.kill(pid, SIGKILL)
            } else {
                AppState.log("SessionKiller: PID \(pid) terminated after SIGTERM")
            }
        }
    }
}
