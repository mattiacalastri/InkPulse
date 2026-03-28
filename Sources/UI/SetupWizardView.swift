import SwiftUI

// MARK: - Setup Wizard

/// Guides users from zero-config to organized teams in 30 seconds.
/// Scans active session directories, detects git repos, suggests team groupings.
struct SetupWizardView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var step = 0
    @State private var candidates: [TeamCandidate] = []

    private let palette = ["#00d4aa", "#FFD700", "#4A9EFF", "#A855F7", "#FF6B35",
                           "#E74C3C", "#2ECC71", "#3498DB", "#9B59B6", "#F39C12"]

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()

            switch step {
            case 0: scanStep
            case 1: editStep
            case 2: reviewStep
            default: scanStep
            }
        }
        .frame(width: 520, height: 480)
        .onAppear { scan() }
    }

    // MARK: - Header

    private var wizardHeader: some View {
        HStack {
            Button("Cancel") { isPresented = false }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Spacer()
            Text(stepTitle)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            Spacer()
            Text("Step \(step + 1)/3")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Detect Projects"
        case 1: return "Name Your Teams"
        case 2: return "Review & Save"
        default: return "Setup"
        }
    }

    // MARK: - Step 0: Scan

    private var scanStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#00d4aa"))

            if candidates.isEmpty {
                Text("No active sessions detected.")
                    .foregroundStyle(.secondary)
                Text("Start some Claude Code sessions, then try again.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Found \(candidates.count) project\(candidates.count == 1 ? "" : "s")")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(candidates) { c in
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: c.color)).frame(width: 8, height: 8)
                            Image(systemName: c.isGitRepo ? "checkmark.seal.fill" : "folder.fill")
                                .font(.caption)
                                .foregroundStyle(c.isGitRepo ? .green : .secondary)
                            Text(c.name)
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.medium)
                            Spacer()
                            Text(c.shortPath)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            HStack {
                Button("Rescan") { scan() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Next") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(candidates.isEmpty)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }

    // MARK: - Step 1: Edit Teams

    private var editStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($candidates) { $candidate in
                        teamEditorCard(candidate: $candidate)
                    }

                    // Add blank team
                    Button(action: { addBlankTeam() }) {
                        Label("Add Team", systemImage: "plus.circle.fill")
                            .font(.system(.caption, design: .rounded))
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
                .padding(16)
            }

            Divider()
            HStack {
                Button("Back") { step = 0 }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Next") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .disabled(candidates.filter(\.included).isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func teamEditorCard(candidate: Binding<TeamCandidate>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: candidate.included)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Circle().fill(Color(hex: candidate.wrappedValue.color))
                    .frame(width: 10, height: 10)

                TextField("Team name", text: candidate.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .rounded))
                    .frame(maxWidth: 150)

                Spacer()

                // Color picker (simple preset buttons)
                HStack(spacing: 3) {
                    ForEach(palette.prefix(6), id: \.self) { hex in
                        Circle().fill(Color(hex: hex))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: candidate.wrappedValue.color == hex ? 2 : 0)
                            )
                            .onTapGesture { candidate.wrappedValue.color = hex }
                    }
                }
            }

            // Roles
            HStack(spacing: 4) {
                Text("Roles:")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                ForEach(candidate.roles) { $role in
                    TextField("Role", text: $role.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .frame(width: 80)
                }
                Button(action: {
                    let n = candidate.wrappedValue.roles.count
                    candidate.wrappedValue.roles.append(
                        RoleCandidate(name: "Role \(n + 1)", icon: "person.fill", prompt: "")
                    )
                }) {
                    Image(systemName: "plus").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
            }

            Text(candidate.wrappedValue.cwd)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: candidate.wrappedValue.color).opacity(0.06)))
        .opacity(candidate.wrappedValue.included ? 1 : 0.5)
    }

    // MARK: - Step 2: Review & Save

    private var reviewStep: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let included = candidates.filter(\.included)
                    ForEach(included) { c in
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: c.color)).frame(width: 10, height: 10)
                            Text(c.name)
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.bold)
                            Text("(\(c.roles.count) roles)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        ForEach(c.roles) { role in
                            HStack(spacing: 6) {
                                Image(systemName: role.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(role.name)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .padding(.leading, 20)
                        }
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                Button("Back") { step = 1 }
                    .buttonStyle(.bordered)
                Spacer()

                let n = candidates.filter(\.included).count
                Button("Save \(n) Team\(n == 1 ? "" : "s")") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    // MARK: - Logic

    private func scan() {
        var detected: [String: String] = [:] // cwd -> suggested name
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        for (_, cwd) in appState.sessionCwds {
            if cwd == home { continue } // Skip home dir (becomes Workspace automatically)
            if detected[cwd] != nil { continue }

            let url = URL(fileURLWithPath: cwd)
            let name = url.lastPathComponent
            let capitalized = name.prefix(1).uppercased() + name.dropFirst()
            detected[cwd] = capitalized
        }

        // Also detect from teams.json if it exists (pre-populate for editing)
        let existing = TeamsLoader.load()
        for team in existing {
            let cwd = team.resolvedCwd
            if detected[cwd] == nil {
                detected[cwd] = team.name
            }
        }

        candidates = detected.enumerated().map { (idx, entry) in
            let (cwd, name) = entry
            let isGit = FileManager.default.fileExists(atPath: cwd + "/.git")
            let colorIdx = idx % palette.count

            // Check if there's an existing team config for this cwd
            let existingTeam = existing.first { $0.resolvedCwd == cwd }

            return TeamCandidate(
                name: existingTeam?.name ?? name,
                cwd: cwd,
                color: existingTeam?.color ?? palette[colorIdx],
                isGitRepo: isGit,
                included: true,
                roles: existingTeam?.roles.map {
                    RoleCandidate(name: $0.name, icon: $0.icon, prompt: $0.prompt)
                } ?? defaultRoles()
            )
        }
        .sorted { $0.name < $1.name }
    }

    private func defaultRoles() -> [RoleCandidate] {
        [
            RoleCandidate(name: "Lead", icon: "brain.head.profile", prompt: ""),
            RoleCandidate(name: "Dev", icon: "hammer.fill", prompt: ""),
            RoleCandidate(name: "Review", icon: "magnifyingglass", prompt: ""),
        ]
    }

    private func addBlankTeam() {
        let idx = candidates.count
        candidates.append(TeamCandidate(
            name: "New Team",
            cwd: FileManager.default.homeDirectoryForCurrentUser.path,
            color: palette[idx % palette.count],
            isGitRepo: false,
            included: true,
            roles: defaultRoles()
        ))
    }

    private func save() {
        let teams = candidates.filter(\.included).map { c in
            TeamConfig(
                id: c.name.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: c.name,
                cwd: c.cwd,
                color: c.color,
                roles: c.roles.map {
                    RoleConfig(id: $0.name.lowercased().replacingOccurrences(of: " ", with: "-"),
                               name: $0.name, prompt: $0.prompt, icon: $0.icon)
                }
            )
        }

        let file = TeamsFile(teams: teams)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(file) {
            try? data.write(to: TeamsLoader.teamsFile)
            appState.reloadTeams()
        }

        isPresented = false
    }
}

// MARK: - Models

struct TeamCandidate: Identifiable {
    let id = UUID()
    var name: String
    var cwd: String
    var color: String
    var isGitRepo: Bool
    var included: Bool
    var roles: [RoleCandidate]

    var shortPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }
}

struct RoleCandidate: Identifiable {
    let id = UUID()
    var name: String
    var icon: String
    var prompt: String
}
