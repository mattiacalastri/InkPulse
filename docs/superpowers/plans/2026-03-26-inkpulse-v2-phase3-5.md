# InkPulse v2 — Phase 3+5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bidirectional WebSocket control channel between InkPulse and Claude Code sessions, plus event-based notifications for deploy/error/task completion.

**Architecture:** URLSessionWebSocketTask server (no SwiftNIO dependency) on localhost:9998. Claude Code hook script auto-connects on SessionStart. EventDetector pattern-matches JSONL for significant events and triggers macOS notifications.

**Tech Stack:** Swift 5.9, SwiftUI, Network.framework (NWListener for WS server), Foundation

**Spec:** `~/projects/InkPulse/SPEC.md` sections 3.3, 3.5

---

## Status — What's Done

| Phase | Status | Key Files |
|-------|--------|-----------|
| Phase 1 — Team UI | ✅ DONE | TeamConfig.swift, TeamSectionView.swift |
| Phase 2 — Spawn | ✅ DONE | TeamSpawner.swift |
| Phase 3 — WebSocket | **THIS PLAN** | WSServer, SessionRegistry, WSProtocol |
| Phase 4 — MCP Hub | DEFERRED | Complex, needs separate plan |
| Phase 5 — Notifications | **THIS PLAN** (partial — NotificationManager exists) | EventDetector.swift |

---

## File Map

| File | Responsibility |
|------|---------------|
| `Sources/WebSocket/WSServer.swift` | **NEW** — NWListener WebSocket server on :9998 |
| `Sources/WebSocket/WSProtocol.swift` | **NEW** — Typed message structs (status, command, notify) |
| `Sources/WebSocket/SessionRegistry.swift` | **NEW** — Track connected sessions, map to team/role |
| `Sources/Notifications/EventDetector.swift` | **NEW** — Pattern match JSONL for deploy/error/task events |
| `Sources/App/AppState.swift` | **MODIFY** — Start WSServer + EventDetector |
| `Sources/UI/TeamSectionView.swift` | **MODIFY** — Add "Send Task" button for connected agents |
| `~/.inkpulse/hooks/ws_connect.sh` | **NEW** — Claude Code SessionStart hook |
| `Package.swift` | **NO CHANGE** — no new dependencies needed |

---

## Task 1: WSProtocol — Message Types

**Files:**
- Create: `Sources/WebSocket/WSProtocol.swift`

- [ ] **Step 1: Create WebSocket directory and protocol file**

```swift
// Sources/WebSocket/WSProtocol.swift
import Foundation

/// Messages from Claude Code session → InkPulse
enum WSInbound: Codable {
    case status(WSStatusMessage)
    case heartbeat(sessionId: String)

    enum CodingKeys: String, CodingKey { case type, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "status":
            self = .status(try container.decode(WSStatusMessage.self, forKey: .data))
        case "heartbeat":
            let data = try container.decode([String: String].self, forKey: .data)
            self = .heartbeat(sessionId: data["session_id"] ?? "")
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .status(let msg):
            try container.encode("status", forKey: .type)
            try container.encode(msg, forKey: .data)
        case .heartbeat(let sid):
            try container.encode("heartbeat", forKey: .type)
            try container.encode(["session_id": sid], forKey: .data)
        }
    }
}

struct WSStatusMessage: Codable {
    let sessionId: String
    let cwd: String
    let state: String        // "working", "idle", "thinking"
    let currentTool: String?
    let currentTarget: String?
    let task: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd, state
        case currentTool = "current_tool"
        case currentTarget = "current_target"
        case task
    }
}

/// Messages from InkPulse → Claude Code session
enum WSOutbound: Codable {
    case command(WSCommandMessage)
    case notify(WSNotifyMessage)

    enum CodingKeys: String, CodingKey { case type, data }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .command(let msg):
            try container.encode("command", forKey: .type)
            try container.encode(msg, forKey: .data)
        case .notify(let msg):
            try container.encode("notify", forKey: .type)
            try container.encode(msg, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "command": self = .command(try container.decode(WSCommandMessage.self, forKey: .data))
        case "notify": self = .notify(try container.decode(WSNotifyMessage.self, forKey: .data))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown: \(type)")
        }
    }
}

struct WSCommandMessage: Codable {
    let action: String       // "task", "pause", "resume"
    let prompt: String?
}

struct WSNotifyMessage: Codable {
    let fromTeam: String
    let fromRole: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case fromTeam = "from_team"
        case fromRole = "from_role"
        case message
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -3`
Expected: Build complete!

- [ ] **Step 3: Commit**

```bash
git add Sources/WebSocket/WSProtocol.swift
git commit -m "feat: WSProtocol — typed WebSocket message structs"
```

---

## Task 2: WSServer — WebSocket Server with Network.framework

**Files:**
- Create: `Sources/WebSocket/WSServer.swift`

- [ ] **Step 1: Create WebSocket server using NWListener**

```swift
// Sources/WebSocket/WSServer.swift
import Foundation
import Network

/// Lightweight WebSocket server on localhost using Network.framework (no dependencies).
final class WSServer {

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:] // connectionId -> connection
    private let port: UInt16
    private let queue = DispatchQueue(label: "inkpulse.ws", qos: .userInitiated)

    var onStatusReceived: ((WSStatusMessage) -> Void)?
    var onSessionConnected: ((String) -> Void)?    // sessionId
    var onSessionDisconnected: ((String) -> Void)?

    /// Maps connectionId -> sessionId (set after first status message)
    private var connectionSessionMap: [String: String] = [:]

    init(port: UInt16 = 9998) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start() {
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            AppState.log("WSServer: failed to create listener — \(error)")
            return
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                AppState.log("WSServer: listening on :\(self.port)")
            case .failed(let error):
                AppState.log("WSServer: listener failed — \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        connectionSessionMap.removeAll()
        AppState.log("WSServer: stopped")
    }

    // MARK: - Connections

    private func handleNewConnection(_ connection: NWConnection) {
        let connId = UUID().uuidString
        connections[connId] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                AppState.log("WSServer: client connected (\(connId.prefix(8)))")
                self?.receiveMessages(connId: connId, connection: connection)
            case .failed(let error):
                AppState.log("WSServer: connection failed — \(error)")
                self?.removeConnection(connId)
            case .cancelled:
                self?.removeConnection(connId)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func removeConnection(_ connId: String) {
        connections.removeValue(forKey: connId)
        if let sessionId = connectionSessionMap.removeValue(forKey: connId) {
            AppState.log("WSServer: session disconnected — \(sessionId)")
            DispatchQueue.main.async { [weak self] in
                self?.onSessionDisconnected?(sessionId)
            }
        }
    }

    // MARK: - Receive

    private func receiveMessages(connId: String, connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if let error {
                AppState.log("WSServer: receive error — \(error)")
                self.removeConnection(connId)
                return
            }

            // Check if this is a WebSocket text message
            if let data,
               let wsMetadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               wsMetadata.opcode == .text {
                self.handleTextMessage(data, connId: connId)
            }

            // Continue receiving
            self.receiveMessages(connId: connId, connection: connection)
        }
    }

    private func handleTextMessage(_ data: Data, connId: String) {
        guard let inbound = try? JSONDecoder().decode(WSInbound.self, from: data) else {
            AppState.log("WSServer: failed to decode message")
            return
        }

        switch inbound {
        case .status(let msg):
            // Map connection to session on first status
            if connectionSessionMap[connId] == nil {
                connectionSessionMap[connId] = msg.sessionId
                DispatchQueue.main.async { [weak self] in
                    self?.onSessionConnected?(msg.sessionId)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.onStatusReceived?(msg)
            }

        case .heartbeat(let sessionId):
            if connectionSessionMap[connId] == nil {
                connectionSessionMap[connId] = sessionId
            }
        }
    }

    // MARK: - Send

    /// Send a message to a specific session.
    func send(_ message: WSOutbound, to sessionId: String) {
        guard let connId = connectionSessionMap.first(where: { $0.value == sessionId })?.key,
              let connection = connections[connId] else {
            AppState.log("WSServer: no connection for session \(sessionId)")
            return
        }

        guard let data = try? JSONEncoder().encode(message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ error in
            if let error {
                AppState.log("WSServer: send error — \(error)")
            }
        }))
    }

    /// Broadcast to all connected sessions.
    func broadcast(_ message: WSOutbound) {
        for sessionId in connectionSessionMap.values {
            send(message, to: sessionId)
        }
    }

    // MARK: - State

    var connectedSessionIds: Set<String> {
        Set(connectionSessionMap.values)
    }

    var connectionCount: Int {
        connections.count
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -3`
Expected: Build complete!

- [ ] **Step 3: Commit**

```bash
git add Sources/WebSocket/WSServer.swift
git commit -m "feat: WSServer — Network.framework WebSocket server on :9998"
```

---

## Task 3: SessionRegistry — Track Connected Sessions

**Files:**
- Create: `Sources/WebSocket/SessionRegistry.swift`

- [ ] **Step 1: Create SessionRegistry**

```swift
// Sources/WebSocket/SessionRegistry.swift
import Foundation

/// Tracks WebSocket-connected sessions and their role assignments.
@MainActor
final class SessionRegistry: ObservableObject {

    struct ConnectedSession {
        let sessionId: String
        var teamId: String?
        var roleId: String?
        var lastStatus: WSStatusMessage?
        let connectedAt: Date
    }

    @Published var sessions: [String: ConnectedSession] = [:]

    func register(sessionId: String) {
        if sessions[sessionId] == nil {
            sessions[sessionId] = ConnectedSession(
                sessionId: sessionId,
                connectedAt: Date()
            )
            AppState.log("SessionRegistry: registered \(sessionId)")
        }
    }

    func unregister(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        AppState.log("SessionRegistry: unregistered \(sessionId)")
    }

    func updateStatus(_ status: WSStatusMessage) {
        if sessions[status.sessionId] == nil {
            register(sessionId: status.sessionId)
        }
        sessions[status.sessionId]?.lastStatus = status
    }

    /// Assign a session to a team/role (from cwd matching or explicit).
    func assignRole(sessionId: String, teamId: String, roleId: String) {
        sessions[sessionId]?.teamId = teamId
        sessions[sessionId]?.roleId = roleId
    }

    var connectedCount: Int { sessions.count }

    func isConnected(_ sessionId: String) -> Bool {
        sessions[sessionId] != nil
    }
}
```

- [ ] **Step 2: Verify build, commit**

```bash
cd ~/projects/InkPulse && swift build 2>&1 | tail -3
git add Sources/WebSocket/SessionRegistry.swift
git commit -m "feat: SessionRegistry — track WS-connected sessions"
```

---

## Task 4: EventDetector — Pattern Match JSONL for Notifications

**Files:**
- Create: `Sources/Notifications/EventDetector.swift`

- [ ] **Step 1: Create EventDetector**

```swift
// Sources/Notifications/EventDetector.swift
import Foundation

/// Detects significant events from JSONL patterns and triggers notifications.
final class EventDetector {

    private let notificationManager: NotificationManager
    private var cooldowns: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 60

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    /// Check a batch of snapshots for notable events.
    func check(sessions: [String: MetricsSnapshot], sessionCwds: [String: String]) {
        let now = Date()

        for (sessionId, snap) in sessions {
            let project = projectName(
                from: sessionId,
                filePath: nil,
                cwd: sessionCwds[sessionId],
                inferredProject: snap.inferredProject
            )

            // Deploy detected (git push or railway deploy in last tool)
            if let tool = snap.lastToolName, let target = snap.lastToolTarget {
                if tool == "Bash" && (target.contains("git push") || target.contains("railway")) {
                    notify(key: "\(sessionId):deploy", title: "Deploy", body: "\(project): \(target)", now: now)
                }
            }

            // Task completed
            if let task = snap.activeTaskName, task.lowercased().contains("completed") {
                notify(key: "\(sessionId):task", title: "Task Done", body: "\(project): \(task)", now: now)
            }

            // Error spike (>10% in 5min window)
            if snap.errorRate > 0.10 {
                notify(key: "\(sessionId):errors", title: "Error Spike", body: "\(project): \(Int(snap.errorRate * 100))% error rate", now: now)
            }

            // Session idle >5min (was active)
            let idle = now.timeIntervalSince(snap.lastEventTime)
            if idle > 300 && snap.costEUR > 0.5 {
                notify(key: "\(sessionId):idle", title: "Agent Idle", body: "\(project): idle \(Int(idle/60))m (€\(String(format: "%.2f", snap.costEUR)) spent)", now: now)
            }
        }
    }

    private func notify(key: String, title: String, body: String, now: Date) {
        if let expiry = cooldowns[key], now < expiry { return }
        cooldowns[key] = now.addingTimeInterval(cooldownInterval)
        notificationManager.send(title: title, body: body)
        AppState.log("EventDetector: \(title) — \(body)")
    }
}
```

- [ ] **Step 2: Verify build, commit**

```bash
cd ~/projects/InkPulse && swift build 2>&1 | tail -3
git add Sources/Notifications/EventDetector.swift
git commit -m "feat: EventDetector — deploy/error/task/idle notifications"
```

---

## Task 5: Wire WSServer + EventDetector into AppState

**Files:**
- Modify: `Sources/App/AppState.swift`

- [ ] **Step 1: Add WSServer and EventDetector properties**

Add after `private var quotaFetcher: QuotaFetcher?`:

```swift
    private(set) var wsServer: WSServer?
    @Published var sessionRegistry = SessionRegistry()
    private var eventDetector: EventDetector?
```

- [ ] **Step 2: Start WSServer and EventDetector in start()**

Add after `// Load team configuration` block:

```swift
        // WebSocket server
        wsServer = WSServer()
        wsServer?.onStatusReceived = { [weak self] status in
            Task { @MainActor in
                self?.sessionRegistry.updateStatus(status)
            }
        }
        wsServer?.onSessionConnected = { [weak self] sessionId in
            Task { @MainActor in
                self?.sessionRegistry.register(sessionId: sessionId)
            }
        }
        wsServer?.onSessionDisconnected = { [weak self] sessionId in
            Task { @MainActor in
                self?.sessionRegistry.unregister(sessionId: sessionId)
            }
        }
        wsServer?.start()

        // Event detector
        eventDetector = EventDetector(notificationManager: notificationManager)
```

- [ ] **Step 3: Add EventDetector check to refresh()**

Add after `// Team matching` block:

```swift
        // Event detection
        eventDetector?.check(sessions: metricsEngine.sessions, sessionCwds: sessionCwds)
```

- [ ] **Step 4: Add sendTask method for UI**

Add after `spawnRole` method:

```swift
    func sendTask(_ prompt: String, to sessionId: String) {
        let message = WSOutbound.command(WSCommandMessage(action: "task", prompt: prompt))
        wsServer?.send(message, to: sessionId)
        AppState.log("Sent task to \(sessionId): \(prompt.prefix(50))")
    }
```

- [ ] **Step 5: Verify build, commit**

```bash
cd ~/projects/InkPulse && swift build 2>&1 | tail -3
git add Sources/App/AppState.swift
git commit -m "feat: wire WSServer + EventDetector into AppState"
```

---

## Task 6: Claude Code Hook — Auto-Connect

**Files:**
- Create: `~/.inkpulse/hooks/ws_connect.sh`

- [ ] **Step 1: Create WebSocket connect hook script**

```bash
#!/bin/bash
# InkPulse WebSocket auto-connect hook
# Add to Claude Code settings.json SessionStart hooks
# Sends periodic status updates to InkPulse WSServer

WS_URL="ws://localhost:9998"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
CWD="$(pwd)"

# Check if websocat is available, if not skip silently
command -v websocat >/dev/null 2>&1 || exit 0

# Send initial status
echo "{\"type\":\"status\",\"data\":{\"session_id\":\"$SESSION_ID\",\"cwd\":\"$CWD\",\"state\":\"starting\",\"current_tool\":null,\"current_target\":null,\"task\":null}}" | websocat -n1 "$WS_URL" 2>/dev/null &

exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/.inkpulse/hooks/ws_connect.sh
```

- [ ] **Step 3: Commit**

Note: This hook needs `websocat` (`brew install websocat`) and manual addition to Claude Code settings. Document in README.

```bash
# No git commit needed — this is a user config file, not in the repo
```

---

## Task 7: WS Connection Indicator in RoleCardView

**Files:**
- Modify: `Sources/UI/TeamSectionView.swift`

- [ ] **Step 1: Add WS connected indicator to RoleCardView header**

In RoleCardView's `roleHeader`, after the model badge, add:

```swift
            // WebSocket connected indicator
            if let sid = slot.sessionId, wsConnected.contains(sid) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(hex: "#00d4aa"))
            }
```

This requires passing `wsConnected: Set<String>` through from PopoverView/LiveTab via `appState.wsServer?.connectedSessionIds ?? []`.

- [ ] **Step 2: Add wsConnected parameter to TeamSectionView and RoleCardView**

Add to TeamSectionView:
```swift
    let wsConnected: Set<String>
```

Pass through to RoleCardView:
```swift
    let wsConnected: Set<String>
```

- [ ] **Step 3: Update PopoverView and LiveTab to pass wsConnected**

In both TeamSectionView instantiations, add:
```swift
    wsConnected: appState.wsServer?.connectedSessionIds ?? []
```

- [ ] **Step 4: Verify build, commit**

```bash
cd ~/projects/InkPulse && swift build 2>&1 | tail -3
git add Sources/UI/TeamSectionView.swift Sources/UI/PopoverView.swift Sources/UI/LiveTab.swift
git commit -m "feat: WS connection indicator in role cards"
```

---

## Summary

| Task | What | Time Est |
|------|------|----------|
| 1 | WSProtocol — message types | 2 min |
| 2 | WSServer — Network.framework WS server | 5 min |
| 3 | SessionRegistry — track connected sessions | 2 min |
| 4 | EventDetector — deploy/error/task notifications | 3 min |
| 5 | Wire into AppState | 3 min |
| 6 | Claude Code hook script | 2 min |
| 7 | WS indicator in UI | 3 min |
| **Total** | | **~20 min** |

After this: Phase 4 (MCP Hub) is a separate plan — requires MCP protocol knowledge + process management. Phase 3+5 gives us bidirectional control + smart notifications, which is the core orchestrator value.
