import XCTest
@testable import InkPulse

// ═══════════════════════════════════════════════════════════════════════════════
// MCPRouter Stress Tests — JSON-RPC ID remapping, concurrency, edge cases
// ═══════════════════════════════════════════════════════════════════════════════

final class MCPRouterTests: XCTestCase {

    // MARK: - Basic ID Rewriting

    func testRewriteAssignsUniqueProxyId() {
        let router = MCPRouter()
        let json1 = makeRequest(id: 1, method: "tools/call")
        let json2 = makeRequest(id: 2, method: "tools/call")

        let (_, proxyId1) = router.rewriteRequest(jsonData: json1, sessionId: "s1", serverName: "fal")!
        let (_, proxyId2) = router.rewriteRequest(jsonData: json2, sessionId: "s2", serverName: "fal")!

        XCTAssertNotEqual(proxyId1, proxyId2, "Each request must get a unique proxy ID")
    }

    func testRewriteReplacesOriginalId() {
        let router = MCPRouter()
        let json = makeRequest(id: 42, method: "tools/call")

        let (rewritten, proxyId) = router.rewriteRequest(jsonData: json, sessionId: "s1", serverName: "tg")!
        let dict = try! JSONSerialization.jsonObject(with: rewritten) as! [String: Any]

        XCTAssertEqual(dict["id"] as? Int, proxyId)
        XCTAssertNotEqual(dict["id"] as? Int, 42, "Original ID must be replaced")
    }

    func testRewriteWithStringId() {
        let router = MCPRouter()
        let json = """
        {"jsonrpc":"2.0","id":"abc-123","method":"tools/call","params":{}}
        """.data(using: .utf8)!

        let (rewritten, _) = router.rewriteRequest(jsonData: json, sessionId: "s1", serverName: "gh")!
        let dict = try! JSONSerialization.jsonObject(with: rewritten) as! [String: Any]

        XCTAssertTrue(dict["id"] is Int, "Proxy ID should always be an integer")
    }

    // MARK: - Response Restoration

    func testRestoreResponseMatchesOriginalSession() {
        let router = MCPRouter()
        let json = makeRequest(id: 99, method: "tools/call")

        let (_, proxyId) = router.rewriteRequest(jsonData: json, sessionId: "session-A", serverName: "fal")!
        let response = makeResponse(id: proxyId, result: "ok")

        let (restored, sessionId) = router.restoreResponse(jsonData: response)!
        let dict = try! JSONSerialization.jsonObject(with: restored) as! [String: Any]

        XCTAssertEqual(sessionId, "session-A")
        XCTAssertEqual(dict["id"] as? Int, 99, "Original ID must be restored")
    }

    func testRestoreResponseWithStringOriginalId() {
        let router = MCPRouter()
        let json = """
        {"jsonrpc":"2.0","id":"my-req","method":"tools/call","params":{}}
        """.data(using: .utf8)!

        let (_, proxyId) = router.rewriteRequest(jsonData: json, sessionId: "s1", serverName: "n8n")!
        let response = makeResponse(id: proxyId, result: "done")

        let (restored, _) = router.restoreResponse(jsonData: response)!
        let dict = try! JSONSerialization.jsonObject(with: restored) as! [String: Any]

        XCTAssertEqual(dict["id"] as? String, "my-req")
    }

    func testRestoreUnknownIdReturnsNil() {
        let router = MCPRouter()
        let response = makeResponse(id: 99999, result: "orphan")

        XCTAssertNil(router.restoreResponse(jsonData: response), "Unknown proxy ID should return nil")
    }

    func testRestoreNotificationReturnsNil() {
        let router = MCPRouter()
        let notification = """
        {"jsonrpc":"2.0","method":"notifications/progress","params":{"token":"x"}}
        """.data(using: .utf8)!

        XCTAssertNil(router.restoreResponse(jsonData: notification), "Notifications have no ID — cannot route")
    }

    // MARK: - Concurrent Sessions Stress Test

    func testConcurrent100RequestsNeverCollide() {
        let router = MCPRouter()
        let sessions = (0..<100).map { "session-\($0)" }
        var proxyIds: [Int] = []

        for (i, session) in sessions.enumerated() {
            let json = makeRequest(id: i, method: "tools/call")
            let (_, proxyId) = router.rewriteRequest(jsonData: json, sessionId: session, serverName: "fal")!
            proxyIds.append(proxyId)
        }

        // All proxy IDs must be unique
        XCTAssertEqual(Set(proxyIds).count, 100, "100 requests must produce 100 unique proxy IDs")

        // All responses must route back to correct sessions
        for (i, proxyId) in proxyIds.enumerated() {
            let response = makeResponse(id: proxyId, result: "ok")
            let (restored, sessionId) = router.restoreResponse(jsonData: response)!
            let dict = try! JSONSerialization.jsonObject(with: restored) as! [String: Any]

            XCTAssertEqual(sessionId, "session-\(i)")
            XCTAssertEqual(dict["id"] as? Int, i, "Original ID must be restored for session \(i)")
        }

        XCTAssertEqual(router.pendingCount, 0, "All requests should be resolved")
    }

    func testConcurrentMultiThreadSafety() {
        let router = MCPRouter()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let iterations = 500
        var successCount = 0
        let lock = NSLock()

        for i in 0..<iterations {
            group.enter()
            queue.async {
                let json = self.makeRequest(id: i, method: "tools/call")
                if let (_, proxyId) = router.rewriteRequest(jsonData: json, sessionId: "s-\(i)", serverName: "srv") {
                    let resp = self.makeResponse(id: proxyId, result: "ok")
                    if let (_, sid) = router.restoreResponse(jsonData: resp) {
                        XCTAssertEqual(sid, "s-\(i)")
                        lock.lock()
                        successCount += 1
                        lock.unlock()
                    }
                }
                group.leave()
            }
        }

        group.wait()
        XCTAssertEqual(successCount, iterations, "All \(iterations) concurrent round-trips must succeed")
        XCTAssertEqual(router.pendingCount, 0)
    }

    // MARK: - Stale Pruning

    func testPruneStaleRemovesOldRequests() {
        let router = MCPRouter()
        let json = makeRequest(id: 1, method: "tools/call")
        let _ = router.rewriteRequest(jsonData: json, sessionId: "old-session", serverName: "fal")

        XCTAssertEqual(router.pendingCount, 1)

        // Prune with 0 second threshold — everything is stale
        let stale = router.pruneStale(olderThan: 0)

        XCTAssertEqual(stale.count, 1)
        XCTAssertEqual(stale.first, "old-session")
        XCTAssertEqual(router.pendingCount, 0)
    }

    func testPruneDoesNotRemoveFreshRequests() {
        let router = MCPRouter()
        let json = makeRequest(id: 1, method: "tools/call")
        let _ = router.rewriteRequest(jsonData: json, sessionId: "fresh", serverName: "fal")

        let stale = router.pruneStale(olderThan: 60)  // 60s threshold

        XCTAssertTrue(stale.isEmpty, "Fresh request should not be pruned")
        XCTAssertEqual(router.pendingCount, 1)
    }

    // MARK: - Invalid Input

    func testRewriteInvalidJsonReturnsNil() {
        let router = MCPRouter()
        let garbage = "not json at all".data(using: .utf8)!

        XCTAssertNil(router.rewriteRequest(jsonData: garbage, sessionId: "s1", serverName: "fal"))
    }

    func testRewriteEmptyDataReturnsNil() {
        let router = MCPRouter()

        XCTAssertNil(router.rewriteRequest(jsonData: Data(), sessionId: "s1", serverName: "fal"))
    }

    func testRestoreInvalidJsonReturnsNil() {
        let router = MCPRouter()
        let garbage = "broken".data(using: .utf8)!

        XCTAssertNil(router.restoreResponse(jsonData: garbage))
    }

    // MARK: - Multiple Servers Same Session

    func testSameSessionMultipleServers() {
        let router = MCPRouter()
        let json1 = makeRequest(id: 1, method: "mcp__fal__generate_image")
        let json2 = makeRequest(id: 2, method: "mcp__telegram__SEND_MESSAGE")

        let (_, pid1) = router.rewriteRequest(jsonData: json1, sessionId: "s1", serverName: "fal")!
        let (_, pid2) = router.rewriteRequest(jsonData: json2, sessionId: "s1", serverName: "telegram")!

        XCTAssertNotEqual(pid1, pid2)
        XCTAssertEqual(router.pendingCount, 2)

        // Resolve in reverse order
        let resp2 = makeResponse(id: pid2, result: "sent")
        let (_, sid2) = router.restoreResponse(jsonData: resp2)!
        XCTAssertEqual(sid2, "s1")

        let resp1 = makeResponse(id: pid1, result: "image_url")
        let (_, sid1) = router.restoreResponse(jsonData: resp1)!
        XCTAssertEqual(sid1, "s1")

        XCTAssertEqual(router.pendingCount, 0)
    }

    // MARK: - Helpers

    private func makeRequest(id: Int, method: String) -> Data {
        let dict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": [:] as [String: Any],
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func makeResponse(id: Int, result: String) -> Data {
        let dict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }
}
