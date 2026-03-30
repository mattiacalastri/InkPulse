import Foundation
import Network

/// TCP proxy server that accepts connections from Claude Code sessions
/// and routes MCP tool calls to the shared server pool.
///
/// Architecture:
///   Session1 (stdio client) --TCP:9998--> MCPProxy --> MCPServerManager --> fal.ai
///   Session2 (stdio client) --TCP:9998--> MCPProxy --> MCPServerManager --> telegram
///
/// Each session connects via a thin stdio client that bridges stdio ↔ TCP.
@MainActor
final class MCPProxy: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var connectedSessions: Int = 0
    @Published private(set) var totalRequests: Int = 0

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]  // sessionId → connection
    private let router = MCPRouter()
    private weak var serverManager: MCPServerManager?
    private let port: UInt16

    init(port: UInt16 = 9998) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start(serverManager: MCPServerManager) {
        self.serverManager = serverManager

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            log("MCPProxy: failed to create listener on :\(port): \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.log("MCPProxy: listening on localhost:\(self?.port ?? 0)")
                case .failed(let error):
                    self?.isRunning = false
                    self?.log("MCPProxy: listener failed: \(error)")
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections.values {
            conn.cancel()
        }
        connections.removeAll()
        isRunning = false
        connectedSessions = 0
        log("MCPProxy: stopped")
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let sessionId = UUID().uuidString

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.log("MCPProxy: session \(sessionId.prefix(8)) connected")
                case .failed, .cancelled:
                    self?.removeConnection(sessionId)
                default:
                    break
                }
            }
        }

        connections[sessionId] = connection
        connectedSessions = connections.count
        connection.start(queue: .global(qos: .userInitiated))
        receiveLoop(sessionId: sessionId, connection: connection)
    }

    private func removeConnection(_ sessionId: String) {
        connections.removeValue(forKey: sessionId)
        connectedSessions = connections.count
        log("MCPProxy: session \(sessionId.prefix(8)) disconnected (\(connectedSessions) remaining)")
    }

    // MARK: - Message Routing

    private func receiveLoop(sessionId: String, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] content, _, isComplete, error in

            Task { @MainActor in
                if let data = content, !data.isEmpty {
                    self?.handleIncoming(sessionId: sessionId, data: data)
                }

                if isComplete || error != nil {
                    self?.removeConnection(sessionId)
                    return
                }

                // Continue receiving
                self?.receiveLoop(sessionId: sessionId, connection: connection)
            }
        }
    }

    private func handleIncoming(sessionId: String, data: Data) {
        totalRequests += 1

        // Parse the JSON-RPC request to find the target server
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("MCPProxy: invalid JSON from \(sessionId.prefix(8))")
            return
        }

        // Extract the tool name from the request to determine routing
        let method = dict["method"] as? String ?? ""

        // Route to the correct MCP server based on tool name prefix
        guard let serverName = resolveServer(for: method),
              let mgr = serverManager else {
            sendError(sessionId: sessionId, id: dict["id"], message: "Unknown tool: \(method)")
            return
        }

        // Rewrite ID and forward
        guard let (rewritten, _) = router.rewriteRequest(
            jsonData: data, sessionId: sessionId, serverName: serverName
        ) else {
            sendError(sessionId: sessionId, id: dict["id"], message: "Failed to rewrite request")
            return
        }

        mgr.send(serverName, data: rewritten)

        // Poll for response (simple sync approach for v1)
        pollResponse(sessionId: sessionId, serverName: serverName)
    }

    private func pollResponse(sessionId: String, serverName: String) {
        guard let mgr = serverManager else { return }

        // Read response from server stdout
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var attempts = 0
            while attempts < 300 {  // 30s timeout (100ms * 300)
                if let responseData = mgr.readAvailable(serverName) {
                    Task { @MainActor in
                        self?.handleServerResponse(responseData)
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
                attempts += 1
            }

            Task { @MainActor in
                self?.log("MCPProxy: timeout waiting for \(serverName) response")
            }
        }
    }

    private func handleServerResponse(_ data: Data) {
        guard let (restored, sessionId) = router.restoreResponse(jsonData: data) else {
            // Could be a notification — log and discard for v1
            return
        }

        guard let connection = connections[sessionId] else {
            log("MCPProxy: session \(sessionId.prefix(8)) gone, dropping response")
            return
        }

        connection.send(content: restored, completion: .contentProcessed { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.log("MCPProxy: send error to \(sessionId.prefix(8)): \(error)")
                }
            }
        })
    }

    // MARK: - Server Resolution

    /// Map a JSON-RPC method (tool name) to the MCP server that handles it.
    /// Convention: tools are prefixed with "mcp__<server>__<tool_name>".
    private func resolveServer(for method: String) -> String? {
        // Direct match: "mcp__telegram__SEND_MESSAGE" → "telegram"
        // The MCP tool naming convention: mcp__<servername>__<toolname>
        let doubleSplit = method.components(separatedBy: "__")
        if doubleSplit.count >= 2 {
            let serverName = doubleSplit[1]
            if serverManager?.servers[serverName] != nil {
                return serverName
            }
            // Try with hyphens (e.g., "wp-aurahome")
            let hyphenated = serverName.replacingOccurrences(of: "_", with: "-")
            if serverManager?.servers[hyphenated] != nil {
                return hyphenated
            }
        }

        // Fallback: check if method matches any server name directly
        if let mgr = serverManager {
            for name in mgr.servers.keys {
                if method.lowercased().contains(name.lowercased()) {
                    return name
                }
            }
        }

        return nil
    }

    // MARK: - Error Response

    private func sendError(sessionId: String, id: Any?, message: String) {
        var error: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": -32601, "message": message],
        ]
        if let id = id { error["id"] = id }

        guard let data = try? JSONSerialization.data(withJSONObject: error),
              let connection = connections[sessionId] else { return }

        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Stats

    var routerPendingCount: Int { router.pendingCount }

    // MARK: - Private

    private func log(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
