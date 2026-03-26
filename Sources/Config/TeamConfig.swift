import Foundation
import SwiftUI

// MARK: - Team Configuration (persisted in ~/.inkpulse/teams.json)

struct TeamConfig: Codable, Identifiable {
    let id: String
    let name: String
    let cwd: String
    let color: String
    let roles: [RoleConfig]

    var resolvedColor: Color { Color(hex: color) }

    /// Expands ~ to home directory.
    var resolvedCwd: String {
        if cwd.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path
                + String(cwd.dropFirst(1))
        }
        return cwd
    }
}

struct RoleConfig: Codable, Identifiable {
    let id: String
    let name: String
    let prompt: String
    let icon: String
}

// MARK: - Team Runtime State

struct TeamState: Identifiable {
    let id: String
    let config: TeamConfig
    var slots: [RoleSlot]

    /// Number of occupied role slots (active sessions).
    var activeCount: Int { slots.filter { $0.session != nil }.count }

    /// Total cost across all occupied slots.
    var totalCost: Double { slots.compactMap { $0.session?.costEUR }.reduce(0, +) }

    /// Combined health (average of occupied slots, or -1 if none).
    var combinedHealth: Int {
        let occupied = slots.compactMap { $0.session?.health }
        guard !occupied.isEmpty else { return -1 }
        return occupied.reduce(0, +) / occupied.count
    }
}

struct RoleSlot: Identifiable {
    let id: String
    let role: RoleConfig
    var session: MetricsSnapshot?
    var sessionId: String?
    var cwd: String?

    var isOccupied: Bool { session != nil }
}

// MARK: - Teams JSON File

struct TeamsFile: Codable {
    let teams: [TeamConfig]
}

// MARK: - TeamsLoader

enum TeamsLoader {

    static let teamsFile = InkPulseDefaults.inkpulseDir.appendingPathComponent("teams.json")

    /// Loads team configuration from ~/.inkpulse/teams.json.
    /// Returns empty array if file doesn't exist or is malformed.
    static func load() -> [TeamConfig] {
        guard FileManager.default.fileExists(atPath: teamsFile.path),
              let data = try? Data(contentsOf: teamsFile),
              let file = try? JSONDecoder().decode(TeamsFile.self, from: data) else {
            return []
        }
        return file.teams
    }

    /// Creates a default teams.json with example configuration.
    static func createDefault() {
        let example = TeamsFile(teams: [
            TeamConfig(
                id: "example",
                name: "My Project",
                cwd: "~/projects/my-project",
                color: "#00d4aa",
                roles: [
                    RoleConfig(id: "pm", name: "PM", prompt: "You are the Project Manager.", icon: "chart.bar.fill"),
                    RoleConfig(id: "dev", name: "Dev", prompt: "You are the Lead Developer.", icon: "hammer.fill"),
                    RoleConfig(id: "researcher", name: "Researcher", prompt: "You are the R&D Researcher.", icon: "magnifyingglass"),
                ]
            )
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(example) else { return }
        try? data.write(to: teamsFile, options: .atomic)
    }

    // MARK: - Session Matching

    /// Matches active sessions to team/role slots by cwd.
    /// Returns TeamState array with sessions slotted into roles,
    /// plus an array of unmatched session IDs.
    static func matchSessions(
        teams: [TeamConfig],
        sessions: [String: MetricsSnapshot],
        sessionCwds: [String: String]
    ) -> (teamStates: [TeamState], unmatchedSessionIds: [String]) {

        var matchedSessionIds = Set<String>()
        var teamStates: [TeamState] = []

        for team in teams {
            let resolvedCwd = team.resolvedCwd

            // Find all sessions whose cwd matches this team's cwd
            let matchingSessions = sessionCwds.filter { _, cwd in
                cwd == resolvedCwd || cwd.hasPrefix(resolvedCwd + "/")
            }

            var slots: [RoleSlot] = []
            var availableSessions = Array(matchingSessions.keys)

            for role in team.roles {
                var slot = RoleSlot(id: role.id, role: role)

                // Assign first available matching session to this role slot
                if let sessionId = availableSessions.first,
                   let snapshot = sessions[sessionId] {
                    slot.session = snapshot
                    slot.sessionId = sessionId
                    slot.cwd = sessionCwds[sessionId]
                    matchedSessionIds.insert(sessionId)
                    availableSessions.removeFirst()
                }

                slots.append(slot)
            }

            teamStates.append(TeamState(id: team.id, config: team, slots: slots))
        }

        let unmatchedIds = sessions.keys.filter { !matchedSessionIds.contains($0) }
        return (teamStates, Array(unmatchedIds))
    }
}
