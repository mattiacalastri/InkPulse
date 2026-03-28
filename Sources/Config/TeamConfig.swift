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

    /// Expands ~ to home directory (handles both "~" and "~/subpath").
    var resolvedCwd: String {
        if cwd == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
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
    /// Sessions that match this team's cwd but exceed the number of defined roles.
    var overflowSessionIds: [String] = []

    var overflowCount: Int { overflowSessionIds.count }

    /// Number of truly active role slots (had events in last 2 min).
    var activeCount: Int {
        slots.filter { slot in
            guard let snap = slot.session else { return false }
            return Date().timeIntervalSince(snap.lastEventTime) < 120
        }.count
    }

    /// Total cost across all occupied slots.
    var totalCost: Double { slots.compactMap { $0.session?.costEUR }.reduce(0, +) }

    /// Combined health (average of occupied slots, or -1 if none).
    var combinedHealth: Int {
        let occupied = slots.compactMap { $0.session?.health }
        guard !occupied.isEmpty else { return -1 }
        return occupied.reduce(0, +) / occupied.count
    }

    /// True if this is the auto-generated Workspace team.
    var isWorkspace: Bool { id == "__workspace__" }
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

    // MARK: - Session Matching

    /// Matches active sessions to team/role slots by cwd.
    /// Returns TeamState array with sessions slotted into roles,
    /// plus an array of unmatched session IDs.
    ///
    /// Stable matching: sessions sorted by startTime (oldest first) for deterministic
    /// assignment. Previous assignments are preserved when possible to prevent flickering.
    static func matchSessions(
        teams: [TeamConfig],
        sessions: [String: MetricsSnapshot],
        sessionCwds: [String: String],
        previousStates: [TeamState] = []
    ) -> (teamStates: [TeamState], unmatchedSessionIds: [String]) {

        // Build lookup of previous role->session assignments for stability
        var previousAssignments: [String: String] = [:] // "teamId/roleId" -> sessionId
        for state in previousStates {
            for slot in state.slots {
                if let sid = slot.sessionId {
                    previousAssignments["\(state.id)/\(slot.id)"] = sid
                }
            }
        }

        var matchedSessionIds = Set<String>()
        var teamStates: [TeamState] = []

        for team in teams {
            let resolvedCwd = team.resolvedCwd

            // Find all sessions whose cwd matches this team's cwd.
            // Sort by sessionId for deterministic order.
            let matchingSessionIds = sessionCwds
                .filter { _, cwd in cwd == resolvedCwd || cwd.hasPrefix(resolvedCwd + "/") }
                .keys
                .filter { sessions[$0] != nil }
                .sorted()

            var availableIds = Set(matchingSessionIds)
            var slots: [RoleSlot] = []

            // First pass: preserve previous assignments if session is still available
            for role in team.roles {
                var slot = RoleSlot(id: role.id, role: role)
                let key = "\(team.id)/\(role.id)"

                if let prevSid = previousAssignments[key],
                   availableIds.contains(prevSid),
                   let snapshot = sessions[prevSid] {
                    // Keep previous assignment — no flicker
                    slot.session = snapshot
                    slot.sessionId = prevSid
                    slot.cwd = sessionCwds[prevSid]
                    matchedSessionIds.insert(prevSid)
                    availableIds.remove(prevSid)
                }

                slots.append(slot)
            }

            // Second pass: fill remaining vacant slots with unassigned sessions
            let remainingIds = availableIds.sorted()
            var remainingIdx = 0
            for i in 0..<slots.count {
                if slots[i].session == nil, remainingIdx < remainingIds.count {
                    let sid = remainingIds[remainingIdx]
                    if let snapshot = sessions[sid] {
                        slots[i].session = snapshot
                        slots[i].sessionId = sid
                        slots[i].cwd = sessionCwds[sid]
                        matchedSessionIds.insert(sid)
                    }
                    remainingIdx += 1
                }
            }

            // Track overflow: sessions that match but have no role slot
            let overflowIds = Array(availableIds.subtracting(matchedSessionIds)).sorted()
            matchedSessionIds.formUnion(overflowIds)

            teamStates.append(TeamState(id: team.id, config: team, slots: slots, overflowSessionIds: overflowIds))
        }

        var unmatchedIds = sessions.keys.filter { !matchedSessionIds.contains($0) }.sorted()

        // Auto-generate Workspace team for home-dir sessions that don't match any team
        if !teams.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let workspaceIds = unmatchedIds.filter { sid in
                guard let cwd = sessionCwds[sid] else { return false }
                return cwd == home
            }
            if !workspaceIds.isEmpty {
                let workspaceConfig = TeamConfig(
                    id: "__workspace__", name: "Workspace",
                    cwd: home, color: "#607D8B", roles: []
                )
                unmatchedIds.removeAll { workspaceIds.contains($0) }
                teamStates.append(TeamState(
                    id: "__workspace__", config: workspaceConfig,
                    slots: [], overflowSessionIds: workspaceIds
                ))
            }
        }
        return (teamStates, unmatchedIds)
    }
}
