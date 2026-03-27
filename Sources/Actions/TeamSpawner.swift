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
                return spawnFallback(role: role, team: team, cwd: cwd, windowTitle: windowTitle)
            }
            AppState.log("Spawned \(team.name)/\(role.name) in \(cwd)")
            return true
        }
        return false
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
