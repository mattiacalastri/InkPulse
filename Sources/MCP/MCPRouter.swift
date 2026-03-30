import Foundation

/// Routes JSON-RPC requests from sessions to shared MCP servers.
/// Handles ID remapping to prevent collisions between concurrent sessions.
final class MCPRouter {

    /// A pending request waiting for a response from the MCP server.
    struct PendingRequest {
        let sessionId: String
        let originalId: JSONRPCId
        let serverName: String
        let sentAt: Date
    }

    /// JSON-RPC ID can be string, int, or null.
    enum JSONRPCId: Hashable, Codable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) { self = .string(s) }
            else if let i = try? container.decode(Int.self) { self = .int(i) }
            else { self = .int(0) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            }
        }

        var jsonValue: Any {
            switch self {
            case .string(let s): return s
            case .int(let i): return i
            }
        }
    }

    private var pending: [Int: PendingRequest] = [:]  // proxyId → pending
    private var nextProxyId: Int = 1
    private let lock = NSLock()

    /// Rewrite a request's ID for proxying. Returns (rewritten JSON data, proxyId).
    func rewriteRequest(
        jsonData: Data,
        sessionId: String,
        serverName: String
    ) -> (Data, Int)? {
        guard var dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let originalIdRaw = dict["id"]
        let originalId: JSONRPCId
        if let s = originalIdRaw as? String { originalId = .string(s) }
        else if let i = originalIdRaw as? Int { originalId = .int(i) }
        else { originalId = .int(0) }

        let proxyId: Int
        lock.lock()
        proxyId = nextProxyId
        nextProxyId += 1
        pending[proxyId] = PendingRequest(
            sessionId: sessionId,
            originalId: originalId,
            serverName: serverName,
            sentAt: Date()
        )
        lock.unlock()

        // Replace ID with proxy ID
        dict["id"] = proxyId

        guard let rewritten = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }

        return (rewritten, proxyId)
    }

    /// Given a response from the MCP server, restore the original session's request ID.
    /// Returns (restored JSON data, sessionId) or nil if not found.
    func restoreResponse(jsonData: Data) -> (Data, String)? {
        guard var dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        guard let proxyId = dict["id"] as? Int else {
            // Notification (no id) — cannot route to specific session
            return nil
        }

        lock.lock()
        guard let req = pending.removeValue(forKey: proxyId) else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        // Restore original ID
        dict["id"] = req.originalId.jsonValue

        guard let restored = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }

        return (restored, req.sessionId)
    }

    /// Check for timed-out requests (older than 30s). Returns removed session IDs.
    func pruneStale(olderThan seconds: TimeInterval = 30) -> [String] {
        let cutoff = Date().addingTimeInterval(-seconds)
        var stale: [String] = []

        lock.lock()
        let staleKeys = pending.filter { $0.value.sentAt < cutoff }.map(\.key)
        for key in staleKeys {
            if let req = pending.removeValue(forKey: key) {
                stale.append(req.sessionId)
            }
        }
        lock.unlock()

        return stale
    }

    /// Number of pending requests.
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }
}
