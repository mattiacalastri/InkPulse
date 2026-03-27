# Fix Spawn, Open, and Quit Actions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three broken agent lifecycle actions — Spawn (double-escape bug), Open (overcomplicated lsof matching), and Quit (never wired to UI) — so InkPulse can fully control Claude Code agent processes.

**Architecture:** Each action is an independent `enum` in `Sources/Actions/`. The fixes are surgical: correct AppleScript quoting in TeamSpawner, simplify TerminalOpener to use window titles set during Spawn, wire SessionKiller into RoleCardView/AgentCardView with confirmation alert, and improve ProcessResolver to use `pgrep -f` instead of manual ps+lsof. AppState gets a new `killSession` method. No new files created.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (NSAppleScript), Foundation (Process)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Actions/TeamSpawner.swift` | Modify | Fix AppleScript quoting for `do script` |
| `Sources/Actions/TerminalOpener.swift` | Modify | Simplify to title-based window matching |
| `Sources/Actions/ProcessResolver.swift` | Modify | Use `pgrep -f` + `/proc` style resolution |
| `Sources/Actions/SessionKiller.swift` | Modify (minor) | Add confirmation-friendly API |
| `Sources/App/AppState.swift` | Modify | Add `killSession` method |
| `Sources/UI/TeamSectionView.swift` | Modify | Add Quit button to occupied RoleCardView |
| `Sources/UI/AgentCardView.swift` | Modify | Add Quit button to legacy AgentCardView |

---

### Task 1: Fix TeamSpawner AppleScript Quoting

**Files:**
- Modify: `Sources/Actions/TeamSpawner.swift`

The root cause: the prompt is escaped for Swift string interpolation AND for AppleScript string literals, creating triple-escaped quotes. AppleScript `do script "..."` expects one layer of escaping only.

- [ ] **Step 1: Fix primary spawn method quoting**

Replace the entire `spawnRole` method body in `TeamSpawner.swift` (lines 34-70):

```swift
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
```

- [ ] **Step 2: Fix fallback method quoting**

Replace the fallback method body (lines 76-115) with corrected quoting:

```swift
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
```

- [ ] **Step 3: Build and verify**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Manual test — spawn a single role**

1. Launch InkPulse
2. Click Spawn on any vacant role (e.g. BTC Bot / Dev)
3. Verify: Terminal.app opens, runs `cd ~/btc_predictions && claude "You are the Lead Developer..."`, window title = "InkPulse — BTC Bot/Dev"

- [ ] **Step 5: Commit**

```bash
git add Sources/Actions/TeamSpawner.swift
git commit -m "fix(spawn): correct AppleScript quoting — single escape layer for do script"
```

---

### Task 2: Simplify TerminalOpener to Title-Based Matching

**Files:**
- Modify: `Sources/Actions/TerminalOpener.swift`

The current lsof-based approach is fragile. Since Spawn already sets window titles to "InkPulse — Team/Role", we can match on that. For legacy sessions (no title), fall back to simple `activate`.

- [ ] **Step 1: Rewrite TerminalOpener.open**

Replace entire file content:

```swift
import AppKit

/// Opens or focuses a Terminal.app window running Claude Code.
/// Matches by window title (set during Spawn) or by cwd via process lookup.
enum TerminalOpener {

    /// Focus the Terminal window for the given cwd.
    /// Strategy:
    ///   1. Match window custom title containing the cwd's last path component
    ///   2. Match window custom title containing "InkPulse"
    ///   3. Fallback: just activate Terminal
    static func open(cwd: String) {
        // Extract meaningful identifier from cwd for title matching
        // e.g. ~/btc_predictions -> "btc_predictions", ~/projects/aurahome -> "aurahome"
        let cwdName = URL(fileURLWithPath: cwd).lastPathComponent

        let script = """
        tell application "Terminal"
            activate
            set matched to false

            -- Pass 1: match custom title containing the directory name
            repeat with w in windows
                try
                    if custom title of w contains "\(cwdName)" then
                        set index of w to 1
                        set matched to true
                        exit repeat
                    end if
                end try
            end repeat

            -- Pass 2: if no match, try matching by tab processes
            if not matched then
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set tabProcs to processes of t
                            repeat with p in tabProcs
                                if p contains "claude" then
                                    -- Found a claude tab, focus it
                                    set selected tab of w to t
                                    set index of w to 1
                                    set matched to true
                                    exit repeat
                                end if
                            end repeat
                        end try
                        if matched then exit repeat
                    end repeat
                    if matched then exit repeat
                end repeat
            end if
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppState.log("Open terminal failed: \(error)")
                // Fallback: just activate Terminal
                NSAppleScript(source: "tell application \"Terminal\" to activate")?.executeAndReturnError(nil)
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Actions/TerminalOpener.swift
git commit -m "fix(open): simplify to title-based window matching, remove fragile lsof lookup"
```

---

### Task 3: Improve ProcessResolver for Quit Support

**Files:**
- Modify: `Sources/Actions/ProcessResolver.swift`

Replace the manual ps+lsof approach with `pgrep -f` which is more reliable on macOS.

- [ ] **Step 1: Rewrite ProcessResolver**

Replace entire file content:

```swift
import Foundation

/// Resolves the PID of a Claude Code process by matching its cwd.
enum ProcessResolver {

    /// Finds the PID of a `claude` process whose cwd matches the given directory.
    /// Uses pgrep to find claude processes, then lsof to verify cwd.
    /// Returns nil if no match is found.
    static func findPID(for cwd: String?) -> pid_t? {
        guard let cwd = cwd, !cwd.isEmpty else { return nil }

        // Step 1: Find all claude process PIDs via pgrep
        guard let pgrepOutput = runProcess("/usr/bin/pgrep", arguments: ["-f", "claude"]) else {
            return nil
        }

        let pids = pgrepOutput
            .components(separatedBy: .newlines)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }

        guard !pids.isEmpty else { return nil }

        // Step 2: For each candidate, check cwd via lsof
        for pid in pids {
            guard let lsofOutput = runProcess("/usr/sbin/lsof", arguments: ["-p", "\(pid)", "-Fn"]) else {
                continue
            }
            // lsof -Fn outputs: "fcwd\nn<path>" — look for our cwd
            if lsofOutput.contains(cwd) {
                return pid
            }
        }

        return nil
    }

    // MARK: - Private

    private static func runProcess(_ path: String, arguments: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Actions/ProcessResolver.swift
git commit -m "fix(process): use pgrep -f for more reliable claude PID resolution"
```

---

### Task 4: Wire Quit into AppState and UI

**Files:**
- Modify: `Sources/App/AppState.swift:252-276`
- Modify: `Sources/UI/TeamSectionView.swift` (RoleCardView)
- Modify: `Sources/UI/AgentCardView.swift` (AgentCardView)

- [ ] **Step 1: Add killSession method to AppState**

Add after the `spawnRole` method (after line 276 in AppState.swift):

```swift
func killSession(cwd: String?, sessionId: String) {
    guard let pid = ProcessResolver.findPID(for: cwd) else {
        AppState.log("Kill failed: no PID found for \(sessionId)")
        notificationManager.send(
            title: "Kill Failed",
            body: "Could not find process for session \(String(sessionId.prefix(8)))"
        )
        return
    }
    SessionKiller.kill(pid: pid)
    AppState.log("Kill requested for \(sessionId) (PID \(pid))")
    notificationManager.send(
        title: "Agent Stopped",
        body: "Sent SIGTERM to PID \(pid)"
    )
}
```

- [ ] **Step 2: Build and verify AppState compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Add Quit button to RoleCardView (occupied state)**

In `Sources/UI/TeamSectionView.swift`, the `RoleCardView` struct needs:

a) A new callback property. Add after `var onSpawn: (() -> Void)?` (line 142):

```swift
var onKill: (() -> Void)?
@State private var showKillConfirm = false
```

b) Add a Quit button next to the Open button. In the `occupiedContent` computed property, replace the Open button block (lines 273-287) with:

```swift
// Action buttons
HStack(spacing: 6) {
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

    if onKill != nil {
        Button(action: { showKillConfirm = true }) {
            HStack(spacing: 3) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8))
                Text("Quit")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.red.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(.red.opacity(0.08)))
        }
        .buttonStyle(.borderless)
        .alert("Stop Agent?", isPresented: $showKillConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Stop", role: .destructive) { onKill?() }
        } message: {
            Text("This will send SIGTERM to \(slot.role.name). The agent will attempt to save its work before exiting.")
        }
    }

    Spacer()
}
```

- [ ] **Step 4: Pass onKill through TeamSectionView**

In `TeamSectionView`, add a new callback property after `var onSpawnRole` (line 13):

```swift
var onKillSession: ((String?, String) -> Void)?  // (cwd, sessionId)
```

Then pass it to RoleCardView in the body. In the `ForEach(teamState.slots)` block, add `onKill` to the RoleCardView init (after `onSpawn:`):

```swift
onKill: slot.sessionId.map { sid in
    { onKillSession?(slot.cwd, sid) }
},
```

- [ ] **Step 5: Wire onKillSession in PopoverView and LiveTab**

In `PopoverView.swift`, in the `teamAgentList` where `TeamSectionView` is created (around line 252), add after `onSpawnRole:`:

```swift
onKillSession: { cwd, sessionId in
    appState.killSession(cwd: cwd, sessionId: sessionId)
},
```

In `LiveTab.swift`, in `teamAgentsContent` where `TeamSectionView` is created (around line 331), add the same:

```swift
onKillSession: { cwd, sessionId in
    appState.killSession(cwd: cwd, sessionId: sessionId)
},
```

- [ ] **Step 6: Add Quit button to legacy AgentCardView**

In `AgentCardView.swift`, add property after `let onTap: () -> Void` (line 53):

```swift
var onKill: (() -> Void)?
@State private var showKillConfirm = false
```

In `cardActionBar`, add a Quit button after the Open button (after line 223):

```swift
if onKill != nil {
    Button(action: { showKillConfirm = true }) {
        HStack(spacing: 4) {
            Image(systemName: "stop.fill")
                .font(.system(size: 9))
            Text("Quit")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.red.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.red.opacity(0.08)))
    }
    .buttonStyle(.borderless)
    .alert("Stop Agent?", isPresented: $showKillConfirm) {
        Button("Cancel", role: .cancel) {}
        Button("Stop", role: .destructive) { onKill?() }
    } message: {
        Text("This will terminate the Claude Code process.")
    }
}
```

Then pass `onKill` in all `AgentCardView(...)` call sites in PopoverView and LiveTab. Each call site adds:

```swift
onKill: {
    appState.killSession(
        cwd: appState.sessionCwds[snap.sessionId],
        sessionId: snap.sessionId
    )
}
```

- [ ] **Step 7: Build and verify everything compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 8: Manual test — full lifecycle**

1. Spawn an agent via InkPulse Spawn button
2. Verify Terminal opens with correct command
3. Click Open on the occupied role card — verify correct window comes to front
4. Click Quit on the occupied role card — confirm dialog appears
5. Confirm — verify agent receives SIGTERM and stops

- [ ] **Step 9: Commit**

```bash
git add Sources/App/AppState.swift Sources/Actions/SessionKiller.swift Sources/Actions/ProcessResolver.swift Sources/UI/TeamSectionView.swift Sources/UI/AgentCardView.swift Sources/UI/PopoverView.swift Sources/UI/LiveTab.swift
git commit -m "feat(quit): wire SessionKiller into UI with confirmation alert on role cards"
```

---

### Task 5: Deploy and Verify

**Files:** None (build + deploy)

- [ ] **Step 1: Release build**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 2: Deploy to /Applications**

```bash
pkill -x InkPulse; sleep 1
cp -f .build/release/InkPulse /Applications/InkPulse.app/Contents/MacOS/InkPulse
open /Applications/InkPulse.app
```

- [ ] **Step 3: Full integration test**

1. Open InkPulse from menu bar
2. Spawn BTC Bot / Dev role -> verify Terminal opens with correct prompt
3. Wait for session to appear in InkPulse (10-15s for JSONL detection)
4. Click Open on the occupied card -> verify correct Terminal window focused
5. Click Quit -> confirm -> verify claude process stops
6. Verify role slot returns to "vacant" state after ~30s

- [ ] **Step 4: Final commit with version bump if tests pass**

```bash
git add -A
git commit -m "chore: deploy InkPulse with fixed spawn/open/quit actions"
```
