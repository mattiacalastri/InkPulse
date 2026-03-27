import Foundation
import Network

/// WebSocket server on localhost using Network.framework (zero dependencies).
final class WSServer {

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    private let port: UInt16
    private let queue = DispatchQueue(label: "inkpulse.ws", qos: .userInitiated)

    var onStatusReceived: ((WSStatusMessage) -> Void)?
    var onSessionConnected: ((String) -> Void)?
    var onSessionDisconnected: ((String) -> Void)?

    private var connectionSessionMap: [String: String] = [:]

    init(port: UInt16 = 9998) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start() {
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AppState.log("WSServer: invalid port \(port)")
            return
        }

        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            AppState.log("WSServer: failed to create listener — \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
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
        for (_, conn) in connections { conn.cancel() }
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

            if let data,
               let wsMetadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               wsMetadata.opcode == .text {
                self.handleTextMessage(data, connId: connId)
            }

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
