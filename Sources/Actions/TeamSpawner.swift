import AppKit
import Foundation

/// Spawns Terminal.app windows running Claude Code with team/role context.
enum TeamSpawner {

    /// Result of a spawn operation.
    struct SpawnResult {
        let teamId: String
        let roleId: String
        let success: Bool
    }

    // MARK: - Spawn Entire Team

    /// Spawns all vacant roles for a team.
    /// Returns results for each role attempted.
    @MainActor
    static func spawnTeam(_ team: TeamConfig, occupiedRoleIds: Set<String>) -> [SpawnResult] {
        var results: [SpawnResult] = []
        for role in team.roles where !occupiedRoleIds.contains(role.id) {
            let success = spawnRole(role, team: team)
            results.append(SpawnResult(teamId: team.id, roleId: role.id, success: success))
        }
        return results
    }

    // MARK: - Spawn Single Role

    /// Spawns a single Terminal.app window for a role.
    /// Window runs: cd <cwd> && claude "<prompt>"
    /// After spawn, auto-accepts Claude CLI prompts (MCP trust + folder trust).
    @MainActor
    @discardableResult
    static func spawnRole(_ role: RoleConfig, team: TeamConfig) -> Bool {
        let cwd = team.resolvedCwd
        let windowTitle = "InkPulse — \(team.name)/\(role.name)"

        // Escape for shell: single-quote the cwd, double-quote the prompt
        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")
        let escapedPrompt = role.prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // One layer of escaping: the shell command runs inside AppleScript's do script "..."
        // AppleScript do script passes the string to /bin/sh as-is.
        // We need to escape backslashes and double-quotes for the AppleScript string literal.
        let shellCmd = "cd '\(escapedCwd)' && claude \"\(escapedPrompt)\""
        let asEscapedCmd = shellCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(asEscapedCmd)"
            delay 0.5
            set custom title of front window to "\(windowTitle)"
            set title displays custom title of front window to true
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppState.log("Spawn failed for \(team.name)/\(role.name): \(error)")
                if isTCCDenied(error) {
                    showTCCAlert()
                    return false
                }
                return spawnFallback(role: role, team: team, cwd: cwd, windowTitle: windowTitle)
            }
            AppState.log("Spawned \(team.name)/\(role.name) in \(cwd)")
            autoAccept(windowTitle: windowTitle)
            return true
        }
        return false
    }

    // MARK: - Auto-Accept Claude CLI Prompts

    /// Sends Enter keystrokes to the spawned window after a delay to auto-accept
    /// Claude CLI trust prompts (MCP server auth + folder trust).
    /// Targets the window by its custom title to avoid hitting the wrong terminal.
    static func autoAcceptByTitle(_ windowTitle: String) {
        autoAccept(windowTitle: windowTitle)
    }

    private static func autoAccept(windowTitle: String) {
        let asTitle = windowTitle.replacingOccurrences(of: "\"", with: "\\\"")

        // Run in background to avoid blocking the spawn loop
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait for Claude CLI to start and show trust prompts
            Thread.sleep(forTimeInterval: 4.0)

            let script = """
            tell application "Terminal"
                repeat with w in every window
                    try
                        if custom title of w is "\(asTitle)" then
                            set frontmost of w to true
                            delay 0.3
                            tell application "System Events"
                                tell process "Terminal"
                                    keystroke return
                                end tell
                            end tell
                            delay 2.0
                            tell application "System Events"
                                tell process "Terminal"
                                    keystroke return
                                end tell
                            end tell
                            exit repeat
                        end if
                    end try
                end repeat
            end tell
            """

            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if error != nil {
                    AppState.log("Auto-accept failed for \(windowTitle) (non-critical)")
                } else {
                    AppState.log("Auto-accept sent for \(windowTitle)")
                }
            }
        }
    }

    // MARK: - TCC Permission Detection

    /// Checks if an AppleScript error indicates TCC (Automation) permission denial.
    private static func isTCCDenied(_ error: NSDictionary) -> Bool {
        // AppleScript error -1743 = "not allowed to send Apple events to Terminal"
        if let code = error["NSAppleScriptErrorNumber"] as? Int, code == -1743 {
            return true
        }
        if let msg = error["NSAppleScriptErrorMessage"] as? String,
           msg.contains("not allowed") || msg.contains("not permitted") {
            return true
        }
        return false
    }

    /// Shows a user-facing alert explaining how to grant Automation permission.
    @MainActor
    private static func showTCCAlert() {
        let alert = NSAlert()
        alert.messageText = "Automation Permission Required"
        alert.informativeText = """
        InkPulse needs permission to control Terminal.app for spawning agents.

        Go to: System Settings > Privacy & Security > Automation
        Then enable "Terminal" under InkPulse.

        If InkPulse doesn't appear, try running this in Terminal:
        tccutil reset AppleEvents com.astradigital.inkpulse
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Privacy & Security settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }

        AppState.log("TCC permission denied — showed alert to user")
    }

    // MARK: - Fallback (if --prompt not supported)

    /// Fallback spawn: opens terminal, runs claude, then injects prompt via keystroke.
    @MainActor
    private static func spawnFallback(role: RoleConfig, team: TeamConfig, cwd: String, windowTitle: String) -> Bool {
        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")

        // Flatten prompt to single line, escape for AppleScript keystroke
        let promptForKeystroke = role.prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let cdCmd = "cd '\(escapedCwd)' && claude"
        let asEscapedCd = cdCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(asEscapedCd)"
            delay 0.5
            set custom title of front window to "\(windowTitle)"
            set title displays custom title of front window to true
        end tell

        delay 3

        tell application "System Events"
            tell process "Terminal"
                keystroke "\(promptForKeystroke)"
                keystroke return
            end tell
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppState.log("Spawn fallback also failed for \(team.name)/\(role.name): \(error)")
                return false
            }
            AppState.log("Spawned (fallback) \(team.name)/\(role.name) in \(cwd)")
            return true
        }
        return false
    }
}
