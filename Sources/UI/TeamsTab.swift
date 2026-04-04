import SwiftUI

struct TeamsTab: View {
    @ObservedObject var appState: AppState

    @State private var expandedSessionId: String?

    private var stats: DashboardStats { DashboardStats(appState: appState) }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── HEADER ──
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(Color(hex: "#00d4aa"))
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Teams")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        let teamCount = appState.teamStates.count
                        Text("\(teamCount) groups · \(stats.snaps.count) agents")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()

                    // Aggregate health + cost
                    if !stats.snaps.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "€%.2f", stats.totalCost))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                            Text("\(stats.snaps.count) active")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: "#00d4aa"))
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                // ── TEAMS LIST ──
                ScrollView {
                    VStack(spacing: 12) {
                        if appState.teamConfigs.isEmpty && !appState.hasDynamicTeams {
                            flatContent
                        } else {
                            teamContent
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 16)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(minWidth: 580, minHeight: 640)
        .background(.ultraThinMaterial)
    }

    // MARK: - Team Content

    private var teamContent: some View {
        VStack(spacing: 12) {
            ForEach(appState.teamStates) { team in
                TeamSectionView(
                    teamState: team,
                    sessions: appState.metricsEngine.sessions,
                    sessionCwds: appState.sessionCwds,
                    sessionBranches: appState.sessionBranches,
                    sessionFilePaths: appState.sessionFilePaths,
                    expandedSessionId: $expandedSessionId,
                    isPopover: false,
                    onSpawnTeam: { config, occupied in
                        appState.spawnTeam(config, occupiedRoleIds: occupied)
                    },
                    onSpawnRole: { role, config in
                        appState.spawnRole(role, team: config)
                    },
                    onKillSession: { cwd, sessionId in
                        appState.killSession(cwd: cwd, sessionId: sessionId)
                    },
                    wsConnected: appState.wsServer?.connectedSessionIds ?? []
                )
            }

            // Unmatched sessions
            let unmatchedSnaps = stats.snaps.filter { appState.unmatchedSessionIds.contains($0.sessionId) }
            if !unmatchedSnaps.isEmpty {
                unmatchedSection(snaps: unmatchedSnaps)
            }

            // Expanded detail
            if let expandedId = expandedSessionId,
               let snap = stats.snaps.first(where: { $0.sessionId == expandedId }) {
                AgentDetailPanel(
                    snapshot: snap,
                    cwd: appState.sessionCwds[snap.sessionId]
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var flatContent: some View {
        Group {
            if stats.snaps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.15))
                    Text("No active agents")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(stats.snaps, id: \.sessionId) { snap in
                            AgentCardView(
                                snapshot: snap,
                                filePath: appState.sessionFilePaths[snap.sessionId],
                                cwd: appState.sessionCwds[snap.sessionId],
                                gitBranch: appState.sessionBranches[snap.sessionId],
                                isExpanded: expandedSessionId == snap.sessionId,
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        expandedSessionId = expandedSessionId == snap.sessionId ? nil : snap.sessionId
                                    }
                                },
                                onKill: {
                                    appState.killSession(
                                        cwd: appState.sessionCwds[snap.sessionId],
                                        sessionId: snap.sessionId
                                    )
                                }
                            )
                        }
                    }

                    if let expandedId = expandedSessionId,
                       let snap = stats.snaps.first(where: { $0.sessionId == expandedId }) {
                        AgentDetailPanel(
                            snapshot: snap,
                            cwd: appState.sessionCwds[snap.sessionId]
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    private func unmatchedSection(snaps: [MetricsSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OTHER")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.vertical, 4)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(snaps, id: \.sessionId) { snap in
                    AgentCardView(
                        snapshot: snap,
                        filePath: appState.sessionFilePaths[snap.sessionId],
                        cwd: appState.sessionCwds[snap.sessionId],
                        gitBranch: appState.sessionBranches[snap.sessionId],
                        isExpanded: expandedSessionId == snap.sessionId,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expandedSessionId = expandedSessionId == snap.sessionId ? nil : snap.sessionId
                            }
                        },
                        onKill: {
                            appState.killSession(
                                cwd: appState.sessionCwds[snap.sessionId],
                                sessionId: snap.sessionId
                            )
                        }
                    )
                }
            }
        }
    }
}
