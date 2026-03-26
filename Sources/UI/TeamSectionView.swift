import SwiftUI

// MARK: - Team Section (collapsible, with role cards)

struct TeamSectionView: View {
    let teamState: TeamState
    let sessionCwds: [String: String]
    let sessionBranches: [String: String]
    let sessionFilePaths: [String: String]
    @Binding var expandedSessionId: String?
    let isPopover: Bool
    var onSpawnTeam: ((TeamConfig, Set<String>) -> Void)?
    var onSpawnRole: ((RoleConfig, TeamConfig) -> Void)?

    @State private var isExpanded = true
    @State private var isSpawning = false

    private var team: TeamConfig { teamState.config }
    private var vacantCount: Int { teamState.slots.filter { !$0.isOccupied }.count }
    private var occupiedRoleIds: Set<String> { Set(teamState.slots.filter { $0.isOccupied }.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Team header (tap to collapse)
            teamHeader

            // Role cards (when expanded)
            if isExpanded {
                HStack(spacing: 8) {
                    ForEach(teamState.slots) { slot in
                        RoleCardView(
                            slot: slot,
                            teamColor: team.resolvedColor,
                            filePath: slot.sessionId.flatMap { sessionFilePaths[$0] },
                            cwd: slot.cwd,
                            gitBranch: slot.sessionId.flatMap { sessionBranches[$0] },
                            isExpanded: slot.sessionId == expandedSessionId,
                            isPopover: isPopover,
                            onTap: {
                                guard let sid = slot.sessionId else { return }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    expandedSessionId = expandedSessionId == sid ? nil : sid
                                }
                            },
                            onSpawn: {
                                onSpawnRole?(slot.role, team)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Team Header

    private var teamHeader: some View {
        HStack(spacing: 8) {
            // Collapse button (left side)
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(team.resolvedColor.opacity(0.6))
                        .frame(width: 12)

                    Circle()
                        .fill(team.resolvedColor)
                        .frame(width: 8, height: 8)

                    Text(team.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isPopover ? Color.primary : Color.white)

                    if teamState.activeCount > 0 {
                        Text("\(teamState.activeCount) active")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(team.resolvedColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(team.resolvedColor.opacity(0.12)))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Aggregate stats
            if teamState.activeCount > 0 {
                HStack(spacing: 8) {
                    if teamState.combinedHealth >= 0 {
                        Text("\(teamState.combinedHealth)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(healthColor(for: teamState.combinedHealth))
                    }
                    Text(String(format: "€%.2f", teamState.totalCost))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Spawn Team button
            if vacantCount > 0, onSpawnTeam != nil {
                Button(action: {
                    isSpawning = true
                    onSpawnTeam?(team, occupiedRoleIds)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isSpawning = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isSpawning ? "hourglass" : "play.fill")
                            .font(.system(size: 8))
                        Text(isSpawning ? "Spawning..." : "Spawn")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(team.resolvedColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(team.resolvedColor.opacity(0.12)))
                }
                .buttonStyle(.borderless)
                .disabled(isSpawning)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Role Card View

struct RoleCardView: View {
    let slot: RoleSlot
    let teamColor: Color
    let filePath: String?
    let cwd: String?
    let gitBranch: String?
    let isExpanded: Bool
    let isPopover: Bool
    let onTap: () -> Void
    var onSpawn: (() -> Void)?

    @State private var isSpawning = false

    private var isOccupied: Bool { slot.isOccupied }

    private var isActive: Bool {
        guard let snap = slot.session else { return false }
        let idle = Date().timeIntervalSince(snap.lastEventTime)
        return idle < 30 && snap.tokenMin > 50
    }

    private var statusVerb: String {
        guard let snap = slot.session else { return "Vacant" }
        let idle = Date().timeIntervalSince(snap.lastEventTime)
        if idle > 120 { return "Sleeping" }
        if idle > 30 { return "Waiting" }
        if snap.tokenMin > 800 { return "Forging" }
        if snap.cacheHit > 0.95 { return "Flowing" }
        if snap.errorRate > 0.10 { return "Struggling" }
        if snap.tokenMin > 200 { return "Working" }
        if snap.tokenMin > 50 { return "Thinking" }
        return "Idle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Role identity
            roleHeader

            if isOccupied {
                occupiedContent
            } else {
                vacantContent
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            if isOccupied { onTap() }
        }
    }

    // MARK: - Role Header

    private var roleHeader: some View {
        HStack(spacing: 6) {
            // Status indicator
            if isOccupied {
                BreathingDot(color: isActive ? Color(hex: "#00d4aa") : .gray, isActive: isActive)
                    .scaleEffect(0.7)
            } else {
                Circle()
                    .stroke(teamColor.opacity(0.3), lineWidth: 1)
                    .frame(width: 8, height: 8)
            }

            // Role icon + name
            Image(systemName: slot.role.icon)
                .font(.system(size: 9))
                .foregroundStyle(isOccupied ? teamColor : teamColor.opacity(0.4))
            Text(slot.role.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isOccupied ? (isPopover ? Color.primary : Color.white) : Color.secondary)

            Spacer()

            // Model badge (occupied only)
            if let snap = slot.session {
                Text(modelShortName(snap.model))
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(modelColor(snap.model))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(modelColor(snap.model).opacity(0.12)))
            }
        }
    }

    // MARK: - Occupied Content

    private var occupiedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status verb
            Text(statusVerb)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? Color(hex: "#00d4aa") : .gray)

            // Current tool
            if let toolName = slot.session?.lastToolName {
                HStack(spacing: 3) {
                    Image(systemName: isActive ? "bolt.fill" : "clock")
                        .font(.system(size: 6))
                        .foregroundStyle(isActive ? Color(hex: "#00d4aa") : .gray.opacity(0.5))
                    let target = slot.session?.lastToolTarget
                    Text("\(toolName)\(target.map { " \u{2192} \($0)" } ?? "")")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(isPopover ? Color.secondary : Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            // Vitals row
            HStack(spacing: 8) {
                if let snap = slot.session {
                    Text(String(format: "%.0f", snap.tokenMin))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(String(format: "€%.2f", snap.costEUR))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let snap = slot.session {
                    Text("\(snap.health)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(healthColor(for: snap.health))
                }
            }

            // Open button
            if let dir = cwd {
                Button(action: { TerminalOpener.open(cwd: dir) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 8))
                        Text("Open")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(teamColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(teamColor.opacity(0.1)))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Vacant Content

    private var vacantContent: some View {
        VStack(spacing: 6) {
            Text("not running")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)

            if let onSpawn {
                Button(action: {
                    isSpawning = true
                    onSpawn()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isSpawning = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isSpawning ? "hourglass" : "play.fill")
                            .font(.system(size: 8))
                        Text(isSpawning ? "Spawning..." : "Spawn")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(teamColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(teamColor.opacity(0.1)))
                }
                .buttonStyle(.borderless)
                .disabled(isSpawning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                isOccupied
                    ? (isPopover ? Color.primary.opacity(0.04) : Color.white.opacity(0.04))
                    : (isPopover ? Color.primary.opacity(0.02) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isOccupied
                            ? (isActive ? teamColor.opacity(0.3) : teamColor.opacity(0.15))
                            : teamColor.opacity(0.08),
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
    }
}
