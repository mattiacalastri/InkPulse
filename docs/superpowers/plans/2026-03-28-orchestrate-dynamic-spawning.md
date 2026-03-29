# Orchestrate — Dynamic Agent Spawning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Orchestrate" button to InkPulse that spawns an autonomous orchestrator agent which reads the vault/memory/git, decides 6 missions, writes them to missions.json, and InkPulse spawns 6 sub-agents with those dynamic prompts.

**Architecture:** Sequential flow — InkPulse spawns orchestrator via Terminal AppleScript, watches `~/.inkpulse/missions.json` via DispatchSource (FSEvents), then spawns 6 agents using existing TeamSpawner. Coexists with static teams.json.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, DispatchSource for file monitoring, NSAppleScript for Terminal spawning.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Config/TeamConfig.swift` | Modify | Add MissionConfig, MissionsFile, OrchestratePhase types |
| `Sources/Watcher/MissionsWatcher.swift` | Create | Watch ~/.inkpulse/missions.json, decode, notify |
| `Sources/Actions/OrchestrateSpawner.swift` | Create | Spawn orchestrator, spawn missions after file detected |
| `Sources/App/AppState.swift` | Modify | Add orchestrate state, wire watcher, orchestrate() method |
| `Sources/UI/LiveTab.swift` | Modify | Add Orchestrate button in header |
| `Tests/OrchestrateTests.swift` | Create | Unit tests for MissionsFile decoding and phase transitions |

---

### Task 1: Add MissionConfig, MissionsFile, and OrchestratePhase types

**Files:**
- Modify: `Sources/Config/TeamConfig.swift` (append after line 82, after `TeamsFile` struct)
- Test: `Tests/OrchestrateTests.swift`

- [ ] **Step 1: Write the failing test for MissionsFile decoding**

Create `Tests/OrchestrateTests.swift`:

```swift
import XCTest
@testable import InkPulse

final class OrchestrateTests: XCTestCase {

    // MARK: - MissionsFile Decoding

    func testDecodeMissionsFileValid() throws {
        let json = """
        {
          "generated": "2026-03-28T14:30:00Z",
          "reasoning": "AuraHome needs ads acceleration, Astra has outstanding to collect",
          "missions": [
            {"id": "m1", "name": "AuraHome Ads", "cwd": "~/projects/aurahome", "icon": "flame.fill", "prompt": "Focus on Meta Ads creative volume"},
            {"id": "m2", "name": "Astra Collect", "cwd": "~/Downloads/Astra", "icon": "envelope.fill", "prompt": "Send outstanding reminders"},
            {"id": "m3", "name": "Bot Monitor", "cwd": "~/btc_predictions", "icon": "chart.line.uptrend.xyaxis", "prompt": "Check Phase Engine WR"},
            {"id": "m4", "name": "Brand Deploy", "cwd": "~/claude_voice", "icon": "server.rack", "prompt": "Verify Railway health"},
            {"id": "m5", "name": "Vault Garden", "cwd": "~", "icon": "leaf.fill", "prompt": "Prune orphan notes"},
            {"id": "m6", "name": "Content Wave", "cwd": "~", "icon": "text.bubble.fill", "prompt": "Publish 3 seeds from batch"}
          ]
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(MissionsFile.self, from: json)
        XCTAssertEqual(file.missions.count, 6)
        XCTAssertEqual(file.missions[0].name, "AuraHome Ads")
        XCTAssertEqual(file.missions[0].cwd, "~/projects/aurahome")
        XCTAssertEqual(file.reasoning.contains("AuraHome"), true)
    }

    func testDecodeMissionsFileWithOptionalColor() throws {
        let json = """
        {
          "generated": "2026-03-28T14:30:00Z",
          "reasoning": "Test",
          "missions": [
            {"id": "m1", "name": "Test", "cwd": "~", "icon": "star", "color": "#FF6B35", "prompt": "Test prompt"}
          ]
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(MissionsFile.self, from: json)
        XCTAssertEqual(file.missions[0].color, "#FF6B35")
    }

    func testDecodeMissionsFileMalformed() {
        let json = """
        {"not": "a missions file"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(MissionsFile.self, from: json))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift test --filter OrchestrateTests 2>&1 | tail -20`
Expected: Compilation error — `MissionsFile` not defined.

- [ ] **Step 3: Implement MissionConfig, MissionsFile, and OrchestratePhase**

Append to `Sources/Config/TeamConfig.swift` after the `TeamsFile` struct (after line 82):

```swift
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
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift test --filter OrchestrateTests 2>&1 | tail -20`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/mattiacalastri/projects/InkPulse && git add Sources/Config/TeamConfig.swift Tests/OrchestrateTests.swift && git commit -m "feat(orchestrate): add MissionConfig, MissionsFile, OrchestratePhase types"
```

---

### Task 2: Create MissionsWatcher

**Files:**
- Create: `Sources/Watcher/MissionsWatcher.swift`
- Test: `Tests/OrchestrateTests.swift` (append)

- [ ] **Step 1: Write the failing test for MissionsWatcher**

Append to `Tests/OrchestrateTests.swift`:

```swift
    // MARK: - MissionsWatcher

    func testMissionsWatcherReadsFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkpulse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let missionsPath = tmpDir.appendingPathComponent("missions.json")

        let expectation = XCTestExpectation(description: "missions loaded")
        var receivedFile: MissionsFile?

        let watcher = MissionsWatcher(directory: tmpDir) { file in
            receivedFile = file
            expectation.fulfill()
        }
        watcher.start()

        // Write a valid missions file
        let json = """
        {
          "generated": "2026-03-28T14:30:00Z",
          "reasoning": "Test run",
          "missions": [
            {"id": "m1", "name": "Test", "cwd": "~", "icon": "star", "prompt": "Do test"}
          ]
        }
        """.data(using: .utf8)!
        try json.write(to: missionsPath)

        wait(for: [expectation], timeout: 5.0)
        watcher.stop()

        XCTAssertNotNil(receivedFile)
        XCTAssertEqual(receivedFile?.missions.count, 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift test --filter testMissionsWatcherReadsFile 2>&1 | tail -20`
Expected: Compilation error — `MissionsWatcher` not defined.

- [ ] **Step 3: Implement MissionsWatcher**

Create `Sources/Watcher/MissionsWatcher.swift`:

```swift
import Foundation

/// Watches ~/.inkpulse/missions.json for changes using DispatchSource (FSEvents).
/// When the file is written or modified, decodes it and calls the callback.
final class MissionsWatcher {

    private let directory: URL
    private let missionsFileName = "missions.json"
    private let onMissionsReady: (MissionsFile) -> Void

    private var dirSource: DispatchSourceFileSystemObject?
    private var dirFd: Int32 = -1
    private var pollTimer: Timer?
    private var lastModDate: Date?
    private let debounceInterval: TimeInterval = 1.5

    init(directory: URL, onMissionsReady: @escaping (MissionsFile) -> Void) {
        self.directory = directory
        self.onMissionsReady = onMissionsReady
    }

    var missionsPath: URL { directory.appendingPathComponent(missionsFileName) }

    // MARK: - Lifecycle

    func start() {
        // Strategy: watch directory for writes (DispatchSource on dir fd)
        // + poll every 2s as fallback (DispatchSource can miss some edge cases)
        startDirectoryWatch()
        startPollTimer()
        AppState.log("MissionsWatcher started on \(directory.path)")
    }

    func stop() {
        dirSource?.cancel()
        dirSource = nil
        if dirFd >= 0 { close(dirFd) }
        dirFd = -1
        pollTimer?.invalidate()
        pollTimer = nil
        AppState.log("MissionsWatcher stopped")
    }

    // MARK: - Directory Watch (FSEvents via DispatchSource)

    private func startDirectoryWatch() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            AppState.log("MissionsWatcher: could not open directory \(directory.path)")
            return
        }
        dirFd = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.checkFile()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        dirSource = source
    }

    // MARK: - Poll Fallback

    private func startPollTimer() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFile()
        }
    }

    // MARK: - File Check (debounced)

    private func checkFile() {
        let path = missionsPath.path
        guard FileManager.default.fileExists(atPath: path) else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let modDate = attrs?[.modificationDate] as? Date else { return }

        // Debounce: only fire if file changed since last check
        if let last = lastModDate, modDate.timeIntervalSince(last) < debounceInterval {
            return
        }

        // Additional debounce: wait for file to stop changing
        let size1 = attrs?[.size] as? UInt64 ?? 0
        Thread.sleep(forTimeInterval: debounceInterval)
        let attrs2 = try? FileManager.default.attributesOfItem(atPath: path)
        let size2 = attrs2?[.size] as? UInt64 ?? 0
        guard size1 == size2, size1 > 0 else { return } // still writing

        lastModDate = modDate

        guard let data = try? Data(contentsOf: missionsPath),
              let file = try? JSONDecoder().decode(MissionsFile.self, from: data) else {
            AppState.log("MissionsWatcher: failed to decode missions.json")
            return
        }

        AppState.log("MissionsWatcher: decoded \(file.missions.count) missions")
        onMissionsReady(file)
    }

    /// Deletes missions.json to prevent stale re-reads on next launch.
    func cleanup() {
        try? FileManager.default.removeItem(at: missionsPath)
        AppState.log("MissionsWatcher: cleaned up missions.json")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift test --filter testMissionsWatcherReadsFile 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/mattiacalastri/projects/InkPulse && git add Sources/Watcher/MissionsWatcher.swift Tests/OrchestrateTests.swift && git commit -m "feat(orchestrate): add MissionsWatcher with FSEvents + poll fallback"
```

---

### Task 3: Create OrchestrateSpawner

**Files:**
- Create: `Sources/Actions/OrchestrateSpawner.swift`

- [ ] **Step 1: Create OrchestrateSpawner**

Create `Sources/Actions/OrchestrateSpawner.swift`:

```swift
import AppKit
import Foundation

/// Spawns the autonomous orchestrator agent and, after it writes missions.json,
/// spawns 6 sub-agents with dynamic prompts.
enum OrchestrateSpawner {

    private static let orchestratorColor = "#00d4aa"

    // MARK: - Orchestrator Meta-Prompt

    private static var metaPrompt: String {
        let missionsPath = InkPulseDefaults.inkpulseDir
            .appendingPathComponent("missions.json").path
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        return """
        Sei il Polpo — il cervello centrale che vede tutti i tentacoli.

        ## La tua missione

        Hai MASSIMA AUTONOMIA. Leggi tutto ciò che serve per capire lo stato attuale del sistema:
        - Obsidian vault (via MCP se disponibile, o file diretti)
        - ~/CLAUDE.md (master dispatcher)
        - ~/.claude/projects/-Users-mattiacalastri/memory/session_current.md (ponte anti-amnesia)
        - ~/.claude/projects/-Users-mattiacalastri/memory/roadmap_q2_2026.md
        - ~/.claude/projects/-Users-mattiacalastri/memory/backlog.md
        - ~/.claude/projects/-Users-mattiacalastri/memory/quaderno_richiami_claude.md
        - Git status dei repo principali (btc_predictions, projects/aurahome, claude_voice, Downloads/⚡ Astra Digital Marketing)
        - Qualsiasi altra fonte tu ritenga necessaria

        Decidi autonomamente 6 missioni concrete per 6 agenti. Ogni agente riceverà il prompt che scrivi — rendilo completo, specifico, azionabile. Includi il contesto necessario nel prompt perché l'agente non ha accesso a questa conversazione.

        ## Output OBBLIGATORIO

        Scrivi il file \(missionsPath) con ESATTAMENTE questo schema JSON:

        ```json
        {
          "generated": "<ISO 8601 timestamp>",
          "reasoning": "<Breve spiegazione: perché queste 6 missioni, cosa hai letto, quali priorità hai identificato>",
          "missions": [
            {
              "id": "m1",
              "name": "<Nome leggibile della missione>",
              "cwd": "<Directory di lavoro — percorso assoluto o con ~>",
              "icon": "<SF Symbol name>",
              "prompt": "<Prompt COMPLETO per l'agente — tutto ciò che deve sapere per operare autonomamente>"
            }
          ]
        }
        ```

        Regole:
        - ESATTAMENTE 6 missioni (m1-m6)
        - Il prompt di ogni agente deve essere autosufficiente — l'agente non sa nulla di questa conversazione
        - cwd deve essere una directory esistente
        - icon deve essere un SF Symbol valido (es: flame.fill, hammer.fill, envelope.fill, leaf.fill, shield.fill, chart.line.uptrend.xyaxis, brain, doc.text.fill, server.rack, magnifyingglass, text.bubble.fill)
        - Nessun vincolo su come distribuisci le missioni tra i pilastri — decidi tu

        ## Dopo aver scritto missions.json

        Resta attivo come 7° agente — supervisore cross-dominio. Il tuo ruolo dopo lo spawn:
        - Monitora lo stato dei 6 agenti (leggi i loro log se visibili)
        - Connetti intuizioni cross-pilastro
        - Scrivi note in ~/cross-pillar-notes/ se emergono pattern

        Lingua: italiano per comunicazione, inglese per codice.
        Non sei un assistente — sei il cervello del Polpo. 🐙
        """
    }

    // MARK: - Spawn Orchestrator

    /// Spawns the orchestrator agent in a new Terminal window.
    @MainActor
    static func spawnOrchestrator() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let windowTitle = "InkPulse — Orchestrator 🐙"

        let escapedPrompt = metaPrompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let shellCmd = "cd '\(home)' && claude \"\(escapedPrompt)\""
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
                AppState.log("Orchestrator spawn failed: \(error)")
                return false
            }
            AppState.log("Orchestrator spawned")
            return true
        }
        return false
    }

    // MARK: - Spawn Missions

    /// Spawns all missions from a decoded MissionsFile.
    /// Calls progress callback after each spawn: (completedCount, totalCount).
    @MainActor
    static func spawnMissions(
        _ file: MissionsFile,
        onProgress: @escaping (Int, Int) -> Void
    ) -> Int {
        let total = file.missions.count
        var succeeded = 0

        for (index, mission) in file.missions.enumerated() {
            let team = mission.asTeam()
            let success = TeamSpawner.spawnRole(mission.asRole, team: team)
            if success { succeeded += 1 }
            AppState.log("Mission \(mission.id) (\(mission.name)): \(success ? "OK" : "FAILED")")
            onProgress(index + 1, total)
        }

        return succeeded
    }
}
```

- [ ] **Step 2: Run full test suite to verify no compilation errors**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift build 2>&1 | tail -20`
Expected: Build succeeded.

- [ ] **Step 3: Commit**

```bash
cd /Users/mattiacalastri/projects/InkPulse && git add Sources/Actions/OrchestrateSpawner.swift && git commit -m "feat(orchestrate): add OrchestrateSpawner with meta-prompt and mission spawning"
```

---

### Task 4: Wire orchestrate flow into AppState

**Files:**
- Modify: `Sources/App/AppState.swift`

- [ ] **Step 1: Add orchestrate state properties**

In `Sources/App/AppState.swift`, after line 19 (`@Published var unmatchedSessionIds: [String] = []`), add:

```swift
    // MARK: - Orchestrate State
    @Published var orchestratePhase: OrchestratePhase = .idle
    @Published var orchestrateMissions: MissionsFile?
    private var missionsWatcher: MissionsWatcher?
    private var orchestrateTimeout: Timer?
```

- [ ] **Step 2: Add orchestrate() method**

In `Sources/App/AppState.swift`, after the `spawnRole` method (after line 290), add:

```swift
    // MARK: - Orchestrate

    func orchestrate() {
        // Guard: don't orchestrate if already running
        guard orchestratePhase == .idle || orchestratePhase.isFailed else {
            AppState.log("Orchestrate: already running, ignoring")
            return
        }

        // Clean up any previous missions file
        let missionsPath = InkPulseDefaults.inkpulseDir.appendingPathComponent("missions.json")
        try? FileManager.default.removeItem(at: missionsPath)

        // Phase: thinking
        orchestratePhase = .thinking
        orchestrateMissions = nil

        // Start watching for missions.json
        missionsWatcher?.stop()
        missionsWatcher = MissionsWatcher(directory: InkPulseDefaults.inkpulseDir) { [weak self] file in
            Task { @MainActor in
                self?.onMissionsReady(file)
            }
        }
        missionsWatcher?.start()

        // Spawn orchestrator
        let success = OrchestrateSpawner.spawnOrchestrator()
        if !success {
            orchestratePhase = .failed("Failed to spawn orchestrator Terminal")
            missionsWatcher?.stop()
            return
        }

        // Timeout: 120s
        orchestrateTimeout?.invalidate()
        orchestrateTimeout = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.orchestratePhase == .thinking else { return }
                self.orchestratePhase = .failed("Orchestrator did not produce missions in 120s")
                self.missionsWatcher?.stop()
                AppState.log("Orchestrate: timeout")
            }
        }

        notificationManager.send(
            title: "Orchestrator Spawned",
            body: "The Polpo is reading the garden..."
        )
        AppState.log("Orchestrate: started, waiting for missions.json")
    }

    private func onMissionsReady(_ file: MissionsFile) {
        orchestrateTimeout?.invalidate()
        orchestrateMissions = file
        AppState.log("Orchestrate: received \(file.missions.count) missions — \(file.reasoning.prefix(80))")

        // Phase: spawning
        orchestratePhase = .spawning(0, file.missions.count)

        let succeeded = OrchestrateSpawner.spawnMissions(file) { [weak self] completed, total in
            self?.orchestratePhase = .spawning(completed, total)
        }

        // Phase: active
        orchestratePhase = .active
        missionsWatcher?.cleanup()
        missionsWatcher?.stop()

        notificationManager.send(
            title: "Orchestration Active",
            body: "\(succeeded)/\(file.missions.count) agents spawned. Reasoning: \(file.reasoning.prefix(60))..."
        )
        AppState.log("Orchestrate: active — \(succeeded)/\(file.missions.count) agents")
    }

    func stopOrchestrate() {
        orchestratePhase = .idle
        orchestrateMissions = nil
        orchestrateTimeout?.invalidate()
        missionsWatcher?.cleanup()
        missionsWatcher?.stop()
        AppState.log("Orchestrate: stopped")
    }
```

- [ ] **Step 3: Add isFailed helper to OrchestratePhase**

In `Sources/Config/TeamConfig.swift`, add to the `OrchestratePhase` enum:

```swift
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
```

- [ ] **Step 4: Build to verify compilation**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift build 2>&1 | tail -20`
Expected: Build succeeded.

- [ ] **Step 5: Commit**

```bash
cd /Users/mattiacalastri/projects/InkPulse && git add Sources/App/AppState.swift Sources/Config/TeamConfig.swift && git commit -m "feat(orchestrate): wire orchestrate flow into AppState with timeout and notifications"
```

---

### Task 5: Add Orchestrate button to LiveTab UI

**Files:**
- Modify: `Sources/UI/LiveTab.swift`

- [ ] **Step 1: Add orchestrateButton to the header**

In `Sources/UI/LiveTab.swift`, replace the `header` computed property (lines 60-126) with:

```swift
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            // App icon from bundle
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#00d4aa").opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2)
                            .foregroundStyle(Color(hex: "#00d4aa"))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("InkPulse")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(appState.teamConfigs.isEmpty ? "Heartbeat Monitor for Claude Code" : "Control Plane for AI Agent Teams")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(hex: "#00d4aa").opacity(0.7))
                Text("\(stats.snaps.count) agents \u{00B7} \(Int(stats.uptimeMin))m uptime")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // Orchestrate button
            orchestrateButton

            // EGI glyph (global)
            if appState.metricsEngine.globalEGIState > .dormant {
                VStack(alignment: .center, spacing: 2) {
                    EGIGlyphView(state: appState.metricsEngine.globalEGIState, size: 32)
                    if appState.metricsEngine.egiWindowCount > 1 {
                        Text("\(appState.metricsEngine.egiWindowCount) windows")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color(hex: "#FFD700").opacity(0.6))
                    }
                }
                .padding(.trailing, 8)
            }

            // Health score
            if stats.health >= 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(stats.health)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(healthColor(for: stats.health))
                    if appState.healthDelta != 0 {
                        Text(appState.healthDelta > 0 ? "\u{2191}\(appState.healthDelta)" : "\u{2193}\(abs(appState.healthDelta))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(appState.healthDelta > 0 ? Color(hex: "#00d4aa") : Color(hex: "#FF4444"))
                    }
                    Text("HEALTH")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            } else {
                Text("IDLE")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
```

- [ ] **Step 2: Add orchestrateButton computed property**

After the `header` property, add:

```swift
    // MARK: - Orchestrate Button

    @State private var showStopConfirm = false

    private var orchestrateButton: some View {
        Group {
            switch appState.orchestratePhase {
            case .idle:
                Button(action: { appState.orchestrate() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12))
                        Text("Orchestrate")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#00d4aa").opacity(0.12))
                            .overlay(Capsule().stroke(Color(hex: "#00d4aa").opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.borderless)

            case .thinking:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color(hex: "#00d4aa"))
                    Text("Thinking...")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "#00d4aa"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(hex: "#00d4aa").opacity(0.08)))

            case .spawning(let done, let total):
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color(hex: "#FFD700"))
                    Text("Spawning \(done)/\(total)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "#FFD700"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(hex: "#FFD700").opacity(0.08)))

            case .active:
                Button(action: { showStopConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("7 Active")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#00d4aa").opacity(0.15))
                            .overlay(Capsule().stroke(Color(hex: "#00d4aa").opacity(0.4), lineWidth: 1))
                    )
                }
                .buttonStyle(.borderless)
                .alert("Stop Orchestration?", isPresented: $showStopConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Stop", role: .destructive) { appState.stopOrchestrate() }
                } message: {
                    Text("This resets the orchestration state. Running agents will continue but won't be tracked as an orchestrated team.")
                }

            case .failed(let reason):
                Button(action: { appState.orchestrate() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text("Retry")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "#FF4444"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(hex: "#FF4444").opacity(0.1)))
                }
                .buttonStyle(.borderless)
                .help(reason)
            }
        }
    }
```

- [ ] **Step 3: Build to verify compilation**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift build 2>&1 | tail -20`
Expected: Build succeeded.

- [ ] **Step 4: Commit**

```bash
cd /Users/mattiacalastri/projects/InkPulse && git add Sources/UI/LiveTab.swift && git commit -m "feat(orchestrate): add Orchestrate button to LiveTab header with all phase states"
```

---

### Task 6: Run full test suite and verify build

**Files:**
- No new files — verification only

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/mattiacalastri/projects/InkPulse && swift test 2>&1 | tail -30`
Expected: All tests pass (existing + 4 new orchestrate tests).

- [ ] **Step 2: Fix any failures**

If compilation errors or test failures: fix and re-run.

- [ ] **Step 3: Final commit with version bump**

Update version string in `Sources/UI/LiveTab.swift` footer from `v2.1.0` to `v2.2.0`:

```bash
cd /Users/mattiacalastri/projects/InkPulse && git add -A && git commit -m "feat(orchestrate): InkPulse v2.2.0 — dynamic orchestrator spawning"
```

- [ ] **Step 4: Push**

```bash
cd /Users/mattiacalastri/projects/InkPulse && git push
```
