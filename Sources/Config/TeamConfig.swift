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
    /// Snapshot lookup for overflow sessions (set by matching logic).
    var overflowSnapshots: [String: MetricsSnapshot] = [:]

    var overflowCount: Int { overflowSessionIds.count }

    /// Number of truly active sessions (slots + overflow, events in last 2 min).
    var activeCount: Int {
        let slotActive = slots.filter { slot in
            guard let snap = slot.session else { return false }
            return Date().timeIntervalSince(snap.lastEventTime) < 120
        }.count
        let overflowActive = overflowSnapshots.values.filter {
            Date().timeIntervalSince($0.lastEventTime) < 120
        }.count
        return slotActive + overflowActive
    }

    /// Total session count (occupied slots + overflow).
    var totalSessions: Int {
        slots.filter(\.isOccupied).count + overflowCount
    }

    /// Total cost across all sessions (slots + overflow).
    var totalCost: Double {
        let slotCost = slots.compactMap { $0.session?.costEUR }.reduce(0, +)
        let overflowCost = overflowSnapshots.values.map(\.costEUR).reduce(0, +)
        return slotCost + overflowCost
    }

    /// Combined health (average of all sessions, or -1 if none).
    var combinedHealth: Int {
        let slotHealth = slots.compactMap { $0.session?.health }
        let overflowHealth = overflowSnapshots.values.map(\.health)
        let all = slotHealth + overflowHealth
        guard !all.isEmpty else { return -1 }
        return all.reduce(0, +) / all.count
    }

    /// True if this is an auto-generated team (dynamic grouping).
    var isDynamic: Bool { id.hasPrefix("__auto_") || id == "__workspace__" }
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

// MARK: - Orchestrate (Dynamic Missions)

struct MissionConfig: Codable, Identifiable {
    let id: String
    let name: String
    let cwd: String
    let icon: String
    let color: String?
    let prompt: String

    /// Expands ~ to home directory.
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

    /// Convert to RoleConfig for reuse with TeamSpawner.
    var asRole: RoleConfig {
        RoleConfig(id: id, name: name, prompt: prompt, icon: icon)
    }

    /// Convert to TeamConfig (single-role team) for reuse with TeamSpawner.
    func asTeam(teamColor: String = "#00d4aa") -> TeamConfig {
        TeamConfig(id: "orch-\(id)", name: name, cwd: cwd, color: color ?? teamColor, roles: [asRole])
    }
}

struct MissionsFile: Codable {
    let generated: String
    let reasoning: String
    let missions: [MissionConfig]
}

enum OrchestratePhase: Equatable {
    case idle
    case thinking
    case spawning(Int, Int)  // (completed, total)
    case active
    case failed(String)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
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
    /// When teams are empty (no teams.json), auto-groups sessions by cwd.
    /// The Orchestrator's missions.json creates dynamic teams that override everything.
    ///
    /// Stable matching: sessions sorted by startTime (oldest first) for deterministic
    /// assignment. Previous assignments are preserved when possible to prevent flickering.
    static func matchSessions(
        teams: [TeamConfig],
        sessions: [String: MetricsSnapshot],
        sessionCwds: [String: String],
        previousStates: [TeamState] = []
    ) -> (teamStates: [TeamState], unmatchedSessionIds: [String]) {

        // Dynamic mode: no static teams — auto-group by cwd
        if teams.isEmpty {
            return autoGroupByCwd(sessions: sessions, sessionCwds: sessionCwds)
        }

        // Static mode: match sessions to predefined team roles
        return matchStaticTeams(
            teams: teams,
            sessions: sessions,
            sessionCwds: sessionCwds,
            previousStates: previousStates
        )
    }

    // MARK: - Dynamic Auto-Grouping

    /// Auto-creates team groupings from active session cwds.
    /// Each unique cwd becomes a team. Sessions in the same directory are grouped together.
    /// Team names are derived from the directory name (smart capitalized).
    private static func autoGroupByCwd(
        sessions: [String: MetricsSnapshot],
        sessionCwds: [String: String]
    ) -> (teamStates: [TeamState], unmatchedSessionIds: [String]) {

        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Group session IDs by their cwd
        var cwdGroups: [String: [String]] = [:]
        for (sid, cwd) in sessionCwds where sessions[sid] != nil {
            cwdGroups[cwd, default: []].append(sid)
        }

        // Sort groups: non-home first (alphabetically), home last
        let sortedCwds = cwdGroups.keys.sorted { a, b in
            if a == home { return false }
            if b == home { return true }
            return a < b
        }

        // Color palette for auto-generated teams
        let colors = ["#00d4aa", "#FF6B35", "#FFD700", "#4A9EFF", "#A855F7",
                       "#FF4444", "#10B981", "#F59E0B", "#EC4899", "#607D8B"]

        var teamStates: [TeamState] = []

        for (index, cwd) in sortedCwds.enumerated() {
            guard let sessionIds = cwdGroups[cwd], !sessionIds.isEmpty else { continue }

            let teamName = deriveTeamName(from: cwd, home: home)
            let teamId = "__auto_\(cwd.hashValue)__"
            let color = colors[index % colors.count]

            let config = TeamConfig(
                id: teamId, name: teamName,
                cwd: cwd, color: color, roles: []
            )

            let sortedIds = sessionIds.sorted()
            var snapshots: [String: MetricsSnapshot] = [:]
            for sid in sortedIds {
                if let snap = sessions[sid] { snapshots[sid] = snap }
            }
            let state = TeamState(
                id: teamId, config: config,
                slots: [], overflowSessionIds: sortedIds,
                overflowSnapshots: snapshots
            )
            teamStates.append(state)
        }

        // Any sessions without cwd go to unmatched
        let allGroupedIds = Set(cwdGroups.values.flatMap { $0 })
        let unmatchedIds = sessions.keys.filter { !allGroupedIds.contains($0) }.sorted()

        return (teamStates, unmatchedIds)
    }

    /// Derives a human-readable team name from a directory path.
    private static func deriveTeamName(from cwd: String, home: String) -> String {
        if cwd == home { return "Workspace" }

        var relative = cwd
        if relative.hasPrefix(home) {
            relative = String(relative.dropFirst(home.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
        }

        // Take the last meaningful directory component
        let components = relative.components(separatedBy: "/")
            .filter { !$0.isEmpty }

        guard let last = components.last else { return "Workspace" }
        return SessionMetrics.smartCapitalize(last)
    }

    // MARK: - Static Team Matching

    private static func matchStaticTeams(
        teams: [TeamConfig],
        sessions: [String: MetricsSnapshot],
        sessionCwds: [String: String],
        previousStates: [TeamState]
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

            var overflowSnaps: [String: MetricsSnapshot] = [:]
            for sid in overflowIds { if let s = sessions[sid] { overflowSnaps[sid] = s } }
            teamStates.append(TeamState(id: team.id, config: team, slots: slots, overflowSessionIds: overflowIds, overflowSnapshots: overflowSnaps))
        }

        var unmatchedIds = sessions.keys.filter { !matchedSessionIds.contains($0) }.sorted()

        // Auto-generate Workspace team for home-dir sessions that don't match any team
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
            var wsSnaps: [String: MetricsSnapshot] = [:]
            for sid in workspaceIds { if let s = sessions[sid] { wsSnaps[sid] = s } }
            unmatchedIds.removeAll { workspaceIds.contains($0) }
            teamStates.append(TeamState(
                id: "__workspace__", config: workspaceConfig,
                slots: [], overflowSessionIds: workspaceIds,
                overflowSnapshots: wsSnaps
            ))
        }
        return (teamStates, unmatchedIds)
    }
}
