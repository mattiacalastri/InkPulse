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
    /// Window runs: cd <cwd> && claude --prompt "<prompt>"
    @MainActor
    @discardableResult
    static func spawnRole(_ role: RoleConfig, team: TeamConfig) -> Bool {
        let cwd = team.resolvedCwd
        let windowTitle = "InkPulse — \(team.name)/\(role.name)"
        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")

        // Pass role prompt as positional argument so claude starts working immediately.
        // Positional arg = first user message. Claude executes it, not just waits idle.
        let rolePrompt = role.prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let shellCommand = "cd '\(escapedCwd)' && claude \\\"\(rolePrompt)\\\""

        let script = """
        tell application "Terminal"
            activate
            set newWindow to do script "\(shellCommand)"
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

                // Fallback: open terminal without --prompt, inject via keystroke
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

        // Escape the prompt for AppleScript keystroke injection
        let promptForKeystroke = role.prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escapedCwd)' && claude"
            delay 0.5
            set custom title of front window to "\(windowTitle)"
            set title displays custom title of front window to true
        end tell

        delay 2.5

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
