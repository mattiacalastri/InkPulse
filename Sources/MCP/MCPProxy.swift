import Foundation
import Network

/// TCP proxy server that accepts connections from Claude Code sessions
/// and routes MCP tool calls to the shared server pool.
@MainActor
final class MCPProxy: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var connectedSessions: Int = 0
    @Published private(set) var totalRequests: Int = 0

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
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

        let capturedPort = port
        listener?.stateUpdateHandler = { [weak self] state in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    strongSelf.isRunning = true
                    strongSelf.log("MCPProxy: listening on localhost:\(capturedPort)")
                case .failed(let error):
                    strongSelf.isRunning = false
                    strongSelf.log("MCPProxy: listener failed: \(error)")
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleNewConnection(connection)
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
            guard let strongSelf = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    strongSelf.log("MCPProxy: session \(sessionId.prefix(8)) connected")
                case .failed, .cancelled:
                    strongSelf.removeConnection(sessionId)
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
            guard let strongSelf = self else { return }

            Task { @MainActor in
                if let data = content, !data.isEmpty {
                    strongSelf.handleIncoming(sessionId: sessionId, data: data)
                }

                if isComplete || error != nil {
                    strongSelf.removeConnection(sessionId)
                    return
                }

                strongSelf.receiveLoop(sessionId: sessionId, connection: connection)
            }
        }
    }

    private func handleIncoming(sessionId: String, data: Data) {
        totalRequests += 1

        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("MCPProxy: invalid JSON from \(sessionId.prefix(8))")
            return
        }

        let method = dict["method"] as? String ?? ""

        guard let serverName = resolveServer(for: method),
              let mgr = serverManager else {
            sendError(sessionId: sessionId, id: dict["id"], message: "Unknown tool: \(method)")
            return
        }

        guard let (rewritten, _) = router.rewriteRequest(
            jsonData: data, sessionId: sessionId, serverName: serverName
        ) else {
            sendError(sessionId: sessionId, id: dict["id"], message: "Failed to rewrite request")
            return
        }

        mgr.send(serverName, data: rewritten)
        pollResponse(sessionId: sessionId, serverName: serverName)
    }

    private func pollResponse(sessionId: String, serverName: String) {
        guard let mgr = serverManager else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var attempts = 0
            while attempts < 300 {
                if let responseData = mgr.readAvailable(serverName) {
                    guard let strongSelf = self else { return }
                    Task { @MainActor in
                        strongSelf.handleServerResponse(responseData)
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
                attempts += 1
            }

            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.log("MCPProxy: timeout waiting for \(serverName) response")
            }
        }
    }

    private func handleServerResponse(_ data: Data) {
        guard let (restored, sessionId) = router.restoreResponse(jsonData: data) else { return }

        guard let connection = connections[sessionId] else {
            log("MCPProxy: session \(sessionId.prefix(8)) gone, dropping response")
            return
        }

        connection.send(content: restored, completion: .contentProcessed { error in
            if let error = error {
                #if DEBUG
                print("MCPProxy: send error: \(error)")
                #endif
            }
        })
    }

    // MARK: - Server Resolution

    private func resolveServer(for method: String) -> String? {
        let doubleSplit = method.components(separatedBy: "__")
        if doubleSplit.count >= 2 {
            let serverName = doubleSplit[1]
            if serverManager?.servers[serverName] != nil {
                return serverName
            }
            let hyphenated = serverName.replacingOccurrences(of: "_", with: "-")
            if serverManager?.servers[hyphenated] != nil {
                return hyphenated
            }
        }

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
        var errorDict: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": -32601, "message": message],
        ]
        if let id = id { errorDict["id"] = id }

        guard let data = try? JSONSerialization.data(withJSONObject: errorDict),
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
