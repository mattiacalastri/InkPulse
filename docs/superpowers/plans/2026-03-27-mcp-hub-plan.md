# MCP Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an MCP proxy inside InkPulse that launches each stdio MCP server once and multiplexes tool calls from N Claude Code sessions through a single HTTP endpoint on :9997.

**Architecture:** MCPServerManager launches stdio processes, MCPRouter builds a tool->server routing table via tools/list, MCPHub serves HTTP on :9997 speaking MCP JSON-RPC, ConfigMigrator auto-rewrites .claude.json to point sessions to the proxy.

**Tech Stack:** Swift, Network.framework (HTTP server), Foundation.Process (stdio), JSON-RPC 2.0

**Spec:** `docs/superpowers/specs/2026-03-27-mcp-hub-design.md`

---

## File Structure

```
Sources/MCP/
  MCPServerManager.swift   — launches stdio MCP servers, manages Process lifecycle
  MCPRouter.swift          — routing table (tool name -> server), request dispatch, ID remapping
  MCPHub.swift             — HTTP server on :9997, MCP JSON-RPC protocol
  ConfigMigrator.swift     — backup/rewrite/restore .claude.json

Modified:
  Sources/App/AppState.swift      — init/shutdown hub, @Published hub state
  Sources/UI/ConfigView.swift     — MCP Hub settings section
  Sources/UI/PopoverView.swift    — "MCP: N/N" footer stat
```

---

### Task 1: MCPServerManager — Launch stdio servers

**Files:**
- Create: `Sources/MCP/MCPServerManager.swift`

- [ ] **Step 1: Write MCPServerProcess model**

```swift
import Foundation

struct MCPServerConfig: Codable {
    let command: String
    let args: [String]?
    let env: [String: String]?
}

final class MCPServerProcess {
    let name: String
    let config: MCPServerConfig
    var process: Process?
    var stdinPipe: Pipe?
    var stdoutPipe: Pipe?
    var isHealthy: Bool = false
    var toolNames: [String] = []
    var restartCount: Int = 0

    init(name: String, config: MCPServerConfig) {
        self.name = name
        self.config = config
    }
}
```

- [ ] **Step 2: Write MCPServerManager class**

```swift
final class MCPServerManager {
    private(set) var servers: [String: MCPServerProcess] = [:]
    private let maxRestarts = 3
    private let backoffIntervals: [TimeInterval] = [1, 2, 4]

    /// Parse .claude.json backup, return only stdio servers
    func loadStdioServers(from url: URL) throws -> [String: MCPServerConfig] {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: Any] else {
            return [:]
        }
        var result: [String: MCPServerConfig] = [:]
        for (name, value) in mcpServers {
            guard let serverDict = value as? [String: Any],
                  let type = serverDict["type"] as? String,
                  type == "stdio",
                  let command = serverDict["command"] as? String else { continue }
            let args = serverDict["args"] as? [String]
            let env = serverDict["env"] as? [String: String]
            result[name] = MCPServerConfig(command: command, args: args, env: env)
        }
        return result
    }

    /// Launch all stdio servers
    func launchAll(configs: [String: MCPServerConfig]) {
        for (name, config) in configs {
            let serverProc = MCPServerProcess(name: name, config: config)
            servers[name] = serverProc
            launch(serverProc)
        }
    }

    /// Launch a single server process
    func launch(_ server: MCPServerProcess) {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: server.config.command)
        process.arguments = server.config.args ?? []
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        // Merge env
        var env = ProcessInfo.processInfo.environment
        if let extra = server.config.env {
            for (k, v) in extra { env[k] = v }
        }
        process.environment = env

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleTermination(serverName: server.name)
            }
        }

        do {
            try process.run()
            server.process = process
            server.stdinPipe = stdinPipe
            server.stdoutPipe = stdoutPipe
            server.isHealthy = true
            AppState.log("MCPHub: launched \(server.name) (pid \(process.processIdentifier))")
        } catch {
            AppState.log("MCPHub: failed to launch \(server.name) — \(error)")
            server.isHealthy = false
        }
    }

    /// Handle server crash with backoff restart
    private func handleTermination(serverName: String) {
        guard let server = servers[serverName] else { return }
        server.isHealthy = false
        guard server.restartCount < maxRestarts else {
            AppState.log("MCPHub: \(serverName) exceeded max restarts")
            return
        }
        let delay = backoffIntervals[min(server.restartCount, backoffIntervals.count - 1)]
        server.restartCount += 1
        AppState.log("MCPHub: \(serverName) died, restarting in \(delay)s (attempt \(server.restartCount))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.launch(server)
        }
    }

    /// Stop all servers
    func stopAll() {
        for (_, server) in servers {
            server.process?.terminate()
        }
        servers.removeAll()
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add Sources/MCP/MCPServerManager.swift
git commit -m "feat(mcp-hub): MCPServerManager — launch stdio servers with restart"
```

---

### Task 2: MCPRouter — Routing table + request dispatch

**Files:**
- Create: `Sources/MCP/MCPRouter.swift`

- [ ] **Step 1: Write JSON-RPC types**

```swift
import Foundation

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: AnyCodable?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

/// Flexible JSON-RPC id (int or string)
enum JSONRPCId: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(JSONRPCId.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected int or string"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}

/// Type-erased Codable for arbitrary JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let dbl = try? container.decode(Double.self) {
            value = dbl
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [Any]: try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try container.encode(v.mapValues { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
}
```

- [ ] **Step 2: Write MCPRouter class**

```swift
final class MCPRouter {
    private let serverManager: MCPServerManager

    /// tool name -> server name
    private(set) var routingTable: [String: String] = [:]

    /// Serial queue per server (stdio is single-threaded)
    private var serverQueues: [String: DispatchQueue] = [:]

    /// Internal auto-increment id for backend requests
    private var nextInternalId: Int = 1

    /// All discovered tools (name + inputSchema JSON) for tools/list response
    private(set) var allTools: [[String: Any]] = []

    /// Tool name collisions
    private(set) var collisions: [(tool: String, server1: String, server2: String)] = []

    init(serverManager: MCPServerManager) {
        self.serverManager = serverManager
    }

    /// Initialize all servers and build routing table
    func buildRoutingTable() {
        for (name, server) in serverManager.servers {
            serverQueues[name] = DispatchQueue(label: "inkpulse.mcp.\(name)")
            guard server.isHealthy else { continue }

            // Send initialize
            let initReq = "{\"jsonrpc\":\"2.0\",\"id\":\(nextInternalId),\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"InkPulse\",\"version\":\"2.1.0\"}}}\n"
            nextInternalId += 1
            sendAndReceive(server: server, request: initReq)

            // Send initialized notification
            let initializedNotif = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n"
            sendRaw(server: server, data: initializedNotif)

            // Send tools/list
            let toolsReq = "{\"jsonrpc\":\"2.0\",\"id\":\(nextInternalId),\"method\":\"tools/list\"}\n"
            nextInternalId += 1
            if let response = sendAndReceive(server: server, request: toolsReq),
               let result = response["result"] as? [String: Any],
               let tools = result["tools"] as? [[String: Any]] {
                for tool in tools {
                    guard let toolName = tool["name"] as? String else { continue }
                    if let existing = routingTable[toolName] {
                        collisions.append((tool: toolName, server1: existing, server2: name))
                        AppState.log("MCPHub: collision — \(toolName) claimed by \(existing) and \(name)")
                    } else {
                        routingTable[toolName] = name
                        allTools.append(tool)
                    }
                    server.toolNames.append(toolName)
                }
                AppState.log("MCPHub: \(name) provides \(tools.count) tools")
            }
        }
        AppState.log("MCPHub: routing table built — \(routingTable.count) tools from \(serverManager.servers.count) servers")
    }

    /// Route a tools/call request to the correct server
    func routeToolCall(toolName: String, arguments: [String: Any], completion: @escaping ([String: Any]?) -> Void) {
        guard let serverName = routingTable[toolName],
              let server = serverManager.servers[serverName],
              server.isHealthy else {
            completion(["jsonrpc": "2.0", "error": ["code": -32603, "message": "Server unavailable for tool: \(toolName)"]])
            return
        }

        let queue = serverQueues[serverName] ?? DispatchQueue.global()
        let internalId = nextInternalId
        nextInternalId += 1

        queue.async { [weak self] in
            let params: [String: Any] = ["name": toolName, "arguments": arguments]
            guard let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let paramsStr = String(data: paramsData, encoding: .utf8) else {
                completion(nil)
                return
            }
            let reqStr = "{\"jsonrpc\":\"2.0\",\"id\":\(internalId),\"method\":\"tools/call\",\"params\":\(paramsStr)}\n"
            let response = self?.sendAndReceive(server: server, request: reqStr, timeout: 30)
            DispatchQueue.main.async { completion(response) }
        }
    }

    // MARK: - stdio I/O

    private func sendRaw(server: MCPServerProcess, data: String) {
        guard let pipe = server.stdinPipe,
              let encoded = data.data(using: .utf8) else { return }
        pipe.fileHandleForWriting.write(encoded)
    }

    private func sendAndReceive(server: MCPServerProcess, request: String, timeout: TimeInterval = 10) -> [String: Any]? {
        guard let stdinPipe = server.stdinPipe,
              let stdoutPipe = server.stdoutPipe,
              let reqData = request.data(using: .utf8) else { return nil }

        stdinPipe.fileHandleForWriting.write(reqData)

        // Read response line (blocking with timeout)
        let handle = stdoutPipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(timeout)

        var buffer = Data()
        while Date() < deadline {
            let available = handle.availableData
            if available.isEmpty {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            buffer.append(available)
            if let str = String(data: buffer, encoding: .utf8), str.contains("\n") {
                // Take first complete line
                let lines = str.components(separatedBy: "\n")
                if let firstLine = lines.first, !firstLine.isEmpty,
                   let lineData = firstLine.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    return json
                }
            }
        }
        AppState.log("MCPHub: timeout waiting for \(server.name)")
        return nil
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add Sources/MCP/MCPRouter.swift
git commit -m "feat(mcp-hub): MCPRouter — routing table, tool dispatch, ID remapping"
```

---

### Task 3: MCPHub — HTTP server

**Files:**
- Create: `Sources/MCP/MCPHub.swift`

- [ ] **Step 1: Write MCPHub HTTP server**

```swift
import Foundation
import Network

final class MCPHub {
    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "inkpulse.mcphub", qos: .userInitiated)
    private let router: MCPRouter
    private(set) var actualPort: UInt16 = 0

    init(router: MCPRouter, port: UInt16 = 9997) {
        self.router = router
        self.port = port
    }

    func start() {
        let ports: [UInt16] = [port, port - 1, port - 2] // 9997, 9996, 9995
        for tryPort in ports {
            guard let nwPort = NWEndpoint.Port(rawValue: tryPort) else { continue }
            do {
                let params = NWParameters.tcp
                listener = try NWListener(using: params, on: nwPort)
                actualPort = tryPort
                break
            } catch {
                AppState.log("MCPHub: port \(tryPort) unavailable — \(error)")
            }
        }

        guard listener != nil else {
            AppState.log("MCPHub: failed to bind any port")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                AppState.log("MCPHub: HTTP listening on :\(self.actualPort)")
            case .failed(let error):
                AppState.log("MCPHub: listener failed — \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        AppState.log("MCPHub: HTTP stopped")
    }

    // MARK: - HTTP handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data else {
                connection.cancel()
                return
            }

            // Parse HTTP request — extract body after \r\n\r\n
            guard let raw = String(data: data, encoding: .utf8),
                  let bodyRange = raw.range(of: "\r\n\r\n") else {
                self.sendHTTPResponse(connection: connection, status: 400, body: "{\"error\":\"bad request\"}")
                return
            }

            let body = String(raw[bodyRange.upperBound...])

            guard let bodyData = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let method = json["method"] as? String else {
                self.sendHTTPResponse(connection: connection, status: 400, body: "{\"error\":\"invalid JSON-RPC\"}")
                return
            }

            let requestId = json["id"] // preserve for response

            switch method {
            case "initialize":
                let response = self.buildInitializeResponse(id: requestId)
                self.sendHTTPResponse(connection: connection, status: 200, body: response)

            case "notifications/initialized":
                self.sendHTTPResponse(connection: connection, status: 200, body: "{\"jsonrpc\":\"2.0\"}")

            case "tools/list":
                let response = self.buildToolsListResponse(id: requestId)
                self.sendHTTPResponse(connection: connection, status: 200, body: response)

            case "tools/call":
                guard let params = json["params"] as? [String: Any],
                      let toolName = params["name"] as? String else {
                    self.sendHTTPResponse(connection: connection, status: 400, body: "{\"error\":\"missing tool name\"}")
                    return
                }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                self.router.routeToolCall(toolName: toolName, arguments: arguments) { result in
                    if var result = result {
                        // Remap id to original request id
                        result["id"] = requestId as Any
                        if let responseData = try? JSONSerialization.data(withJSONObject: result),
                           let responseStr = String(data: responseData, encoding: .utf8) {
                            self.sendHTTPResponse(connection: connection, status: 200, body: responseStr)
                        }
                    } else {
                        self.sendHTTPResponse(connection: connection, status: 500, body: "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"internal error\"}}")
                    }
                }
                return // don't close connection yet — async response

            default:
                self.sendHTTPResponse(connection: connection, status: 404, body: "{\"error\":\"unknown method: \(method)\"}")
            }
        }
    }

    private func sendHTTPResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : "Error"
        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // MARK: - Response builders

    private func buildInitializeResponse(id: Any?) -> String {
        let idStr = formatId(id)
        return "{\"jsonrpc\":\"2.0\",\"id\":\(idStr),\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"InkPulse MCP Hub\",\"version\":\"2.1.0\"}}}"
    }

    private func buildToolsListResponse(id: Any?) -> String {
        let idStr = formatId(id)
        guard let toolsData = try? JSONSerialization.data(withJSONObject: router.allTools),
              let toolsStr = String(data: toolsData, encoding: .utf8) else {
            return "{\"jsonrpc\":\"2.0\",\"id\":\(idStr),\"result\":{\"tools\":[]}}"
        }
        return "{\"jsonrpc\":\"2.0\",\"id\":\(idStr),\"result\":{\"tools\":\(toolsStr)}}"
    }

    private func formatId(_ id: Any?) -> String {
        if let intId = id as? Int { return "\(intId)" }
        if let strId = id as? String { return "\"\(strId)\"" }
        return "null"
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/MCP/MCPHub.swift
git commit -m "feat(mcp-hub): MCPHub — HTTP server on :9997, MCP JSON-RPC protocol"
```

---

### Task 4: ConfigMigrator — backup/rewrite/restore

**Files:**
- Create: `Sources/MCP/ConfigMigrator.swift`

- [ ] **Step 1: Write ConfigMigrator**

```swift
import Foundation

final class ConfigMigrator {
    private let claudeJsonURL: URL
    private let backupURL: URL
    private var hubPort: UInt16

    init(hubPort: UInt16 = 9997) {
        self.hubPort = hubPort
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeJsonURL = home.appendingPathComponent(".claude.json")
        self.backupURL = home.appendingPathComponent(".claude.json.inkpulse-backup")
    }

    func updatePort(_ port: UInt16) {
        self.hubPort = port
    }

    /// Check for crash recovery — if backup exists, restore it first
    func recoverIfNeeded() {
        if FileManager.default.fileExists(atPath: backupURL.path) {
            AppState.log("ConfigMigrator: backup found — recovering from previous crash")
            restore()
        }
    }

    /// Backup .claude.json and rewrite with hub proxy
    func migrate() -> Bool {
        guard FileManager.default.fileExists(atPath: claudeJsonURL.path) else {
            AppState.log("ConfigMigrator: .claude.json not found")
            return false
        }

        // Create backup
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: claudeJsonURL, to: backupURL)
        } catch {
            AppState.log("ConfigMigrator: backup failed — \(error)")
            return false
        }

        // Read and modify
        guard let data = try? Data(contentsOf: claudeJsonURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var mcpServers = json["mcpServers"] as? [String: Any] else {
            AppState.log("ConfigMigrator: failed to parse .claude.json")
            return false
        }

        // Remove all stdio servers
        let stdioNames = mcpServers.compactMap { (name, value) -> String? in
            guard let dict = value as? [String: Any],
                  let type = dict["type"] as? String,
                  type == "stdio" else { return nil }
            return name
        }
        for name in stdioNames {
            mcpServers.removeValue(forKey: name)
        }

        // Add hub proxy
        mcpServers["inkpulse-hub"] = [
            "type": "http",
            "url": "http://localhost:\(hubPort)/mcp"
        ]

        json["mcpServers"] = mcpServers

        // Write back
        guard let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            AppState.log("ConfigMigrator: failed to serialize modified .claude.json")
            return false
        }

        do {
            try newData.write(to: claudeJsonURL)
            AppState.log("ConfigMigrator: migrated — removed \(stdioNames.count) stdio servers, added inkpulse-hub on :\(hubPort)")
            return true
        } catch {
            AppState.log("ConfigMigrator: write failed — \(error)")
            return false
        }
    }

    /// Restore .claude.json from backup
    func restore() {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            if FileManager.default.fileExists(atPath: claudeJsonURL.path) {
                try FileManager.default.removeItem(at: claudeJsonURL)
            }
            try FileManager.default.copyItem(at: backupURL, to: claudeJsonURL)
            try FileManager.default.removeItem(at: backupURL)
            AppState.log("ConfigMigrator: restored .claude.json from backup")
        } catch {
            AppState.log("ConfigMigrator: restore failed — \(error)")
        }
    }

    /// Install signal handlers for crash recovery
    func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signal in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let backup = home.appendingPathComponent(".claude.json.inkpulse-backup")
            let target = home.appendingPathComponent(".claude.json")
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: backup, to: target)
                try? FileManager.default.removeItem(at: backup)
            }
            exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
        signal(SIGHUP, handler)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/MCP/ConfigMigrator.swift
git commit -m "feat(mcp-hub): ConfigMigrator — backup/rewrite/restore .claude.json"
```

---

### Task 5: Wire into AppState

**Files:**
- Modify: `Sources/App/AppState.swift`

- [ ] **Step 1: Add MCP Hub properties to AppState**

Add after the WebSocket properties block (~line 32):

```swift
// MARK: - MCP Hub
private(set) var mcpServerManager: MCPServerManager?
private(set) var mcpRouter: MCPRouter?
private(set) var mcpHub: MCPHub?
private(set) var configMigrator: ConfigMigrator?
@Published var mcpHubEnabled: Bool = false
@Published var mcpHubServerCount: Int = 0
@Published var mcpHubToolCount: Int = 0
@Published var mcpHubHealthy: [String: Bool] = [:] // server name -> healthy
```

- [ ] **Step 2: Add startMCPHub() method**

Add after `start()` method:

```swift
// MARK: - MCP Hub

func startMCPHub() {
    let migrator = ConfigMigrator()
    configMigrator = migrator

    // Recover from crash if needed
    migrator.recoverIfNeeded()
    migrator.installSignalHandlers()

    // Load stdio servers from .claude.json (before migration)
    let manager = MCPServerManager()
    mcpServerManager = manager

    let home = FileManager.default.homeDirectoryForCurrentUser
    let claudeJson = home.appendingPathComponent(".claude.json")

    guard let configs = try? manager.loadStdioServers(from: claudeJson) else {
        AppState.log("MCPHub: no stdio servers found")
        return
    }

    guard !configs.isEmpty else {
        AppState.log("MCPHub: no stdio servers to proxy")
        return
    }

    // Launch servers
    manager.launchAll(configs: configs)

    // Build routing table
    let router = MCPRouter(serverManager: manager)
    mcpRouter = router

    // Give servers a moment to start, then build routing table
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        router.buildRoutingTable()

        // Start HTTP hub
        let hub = MCPHub(router: router)
        self?.mcpHub = hub
        hub.start()

        // Migrate config
        migrator.updatePort(hub.actualPort)
        let migrated = migrator.migrate()

        // Update UI state
        self?.mcpHubEnabled = true
        self?.mcpHubServerCount = manager.servers.count
        self?.mcpHubToolCount = router.routingTable.count
        self?.mcpHubHealthy = Dictionary(uniqueKeysWithValues: manager.servers.map { ($0.key, $0.value.isHealthy) })

        AppState.log("MCPHub: ready — \(manager.servers.count) servers, \(router.routingTable.count) tools, migrated=\(migrated)")
    }
}

func stopMCPHub() {
    mcpHub?.stop()
    mcpServerManager?.stopAll()
    configMigrator?.restore()
    mcpHubEnabled = false
    mcpHubServerCount = 0
    mcpHubToolCount = 0
    mcpHubHealthy = [:]
    AppState.log("MCPHub: stopped and config restored")
}
```

- [ ] **Step 3: Add shutdown to existing stop logic**

In `AppState`, find the existing cleanup/quit logic and add `stopMCPHub()` call.

- [ ] **Step 4: Verify it compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppState.swift
git commit -m "feat(mcp-hub): wire MCPHub into AppState lifecycle"
```

---

### Task 6: UI — ConfigView MCP Hub section

**Files:**
- Modify: `Sources/UI/ConfigView.swift`

- [ ] **Step 1: Add MCP Hub section to ConfigView**

Add after the last settings section in the ScrollView:

```swift
// ── MCP HUB ──
sectionHeader("MCP Hub")

HStack {
    Image(systemName: appState.mcpHubEnabled ? "circle.fill" : "circle")
        .foregroundColor(appState.mcpHubEnabled ? .green : .secondary)
        .font(.caption)
    Text(appState.mcpHubEnabled
         ? "Running — \(appState.mcpHubServerCount) servers, \(appState.mcpHubToolCount) tools"
         : "Off")
        .font(.system(.caption, design: .monospaced))
    Spacer()
    Button(appState.mcpHubEnabled ? "Stop" : "Start") {
        if appState.mcpHubEnabled {
            appState.stopMCPHub()
        } else {
            appState.startMCPHub()
        }
    }
    .buttonStyle(.borderless)
    .font(.caption)
}
.padding(.horizontal, 12)

if appState.mcpHubEnabled {
    VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(appState.mcpHubHealthy.keys.sorted()), id: \.self) { name in
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.mcpHubHealthy[name] == true ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(name)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
    .padding(.horizontal, 12)
    .padding(.top, 4)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/projects/InkPulse && swift build 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/ConfigView.swift
git commit -m "feat(mcp-hub): ConfigView MCP Hub section with toggle + server list"
```

---

### Task 7: UI — PopoverView footer stat

**Files:**
- Modify: `Sources/UI/PopoverView.swift`

- [ ] **Step 1: Add MCP stat to PopoverView footer**

Find the existing stats row in PopoverView (the one showing tok/min, cost, cache) and add:

```swift
if appState.mcpHubEnabled {
    Text("MCP: \(appState.mcpHubHealthy.values.filter { $0 }.count)/\(appState.mcpHubServerCount)")
        .font(.system(.caption2, design: .monospaced))
        .foregroundColor(.secondary)
}
```

- [ ] **Step 2: Verify it compiles and visually check**

Run: `cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -3`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/PopoverView.swift
git commit -m "feat(mcp-hub): PopoverView MCP server count in footer"
```

---

### Task 8: Integration test + deploy

- [ ] **Step 1: Build release**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

- [ ] **Step 2: Deploy to /Applications**

```bash
pkill -x InkPulse; sleep 1
cp -f .build/release/InkPulse /Applications/InkPulse.app/Contents/MacOS/InkPulse
open /Applications/InkPulse.app
```

- [ ] **Step 3: Manual test**
- Open InkPulse popover
- Go to Settings, verify MCP Hub section shows "Off"
- Click "Start" — verify servers launch, tool count appears
- Check `~/.claude.json` has `inkpulse-hub` entry and stdio servers removed
- Open a new Claude Code session — verify MCP tools work through proxy
- Click "Stop" — verify .claude.json restored to original
- Quit InkPulse — verify .claude.json restored

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(mcp-hub): Phase 4 complete — shared MCP server pool via HTTP proxy"
```

- [ ] **Step 5: Push**

```bash
git push origin master
```
