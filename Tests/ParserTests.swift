import XCTest
@testable import InkPulse

final class ParserTests: XCTestCase {

    // MARK: - Helpers

    private let ts = "2026-03-23T10:00:00.123Z"
    private let sid = "sess-abc-123"

    private func json(_ dict: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - 1. testParseAssistantEvent

    func testParseAssistantEvent() {
        let line = json([
            "type": "assistant",
            "timestamp": ts,
            "sessionId": sid,
            "message": [
                "model": "claude-sonnet-4-6",
                "usage": [
                    "input_tokens": 1200,
                    "output_tokens": 350,
                    "cache_read_input_tokens": 800,
                    "cache_creation_input_tokens": 100
                ],
                "content": [
                    ["type": "thinking", "thinking": "Let me analyze this..."],
                    ["type": "text", "text": "Here is the answer."]
                ]
            ] as [String: Any]
        ])

        let event = JSONLParser.parse(line: line)

        guard case .assistant(let msg, let date, let sessId) = event else {
            XCTFail("Expected .assistant, got \(event)")
            return
        }

        XCTAssertEqual(msg.model, "claude-sonnet-4-6")
        XCTAssertEqual(msg.usage.inputTokens, 1200)
        XCTAssertEqual(msg.usage.outputTokens, 350)
        XCTAssertEqual(msg.usage.cacheReadInputTokens, 800)
        XCTAssertEqual(msg.usage.cacheCreationInputTokens, 100)
        XCTAssertEqual(msg.thinkingText, "Let me analyze this...")
        XCTAssertEqual(msg.outputText, "Here is the answer.")
        XCTAssertNotNil(date)
        XCTAssertEqual(sessId, sid)
    }

    // MARK: - 2. testParseProgressEvent

    func testParseProgressEvent() {
        let line = json([
            "type": "progress",
            "timestamp": ts,
            "sessionId": sid,
            "toolUseID": "tool-xyz",
            "data": "hook_progress: checking lint"
        ])

        let event = JSONLParser.parse(line: line)

        guard case .progress(let toolId, let isToolUse, let isError, _, _) = event else {
            XCTFail("Expected .progress, got \(event)")
            return
        }

        XCTAssertEqual(toolId, "tool-xyz")
        XCTAssertFalse(isToolUse, "hook_progress should NOT be flagged as tool use")
        XCTAssertFalse(isError)
    }

    // MARK: - 3. testParseProgressErrorEvent

    func testParseProgressErrorEvent() {
        let line = json([
            "type": "progress",
            "timestamp": ts,
            "sessionId": sid,
            "toolUseID": "tool-err",
            "data": "Permission denied for /etc/shadow"
        ])

        let event = JSONLParser.parse(line: line)

        guard case .progress(_, _, let isError, _, _) = event else {
            XCTFail("Expected .progress, got \(event)")
            return
        }

        XCTAssertTrue(isError)
    }

    // MARK: - 4. testParseQueueOperation

    func testParseQueueOperation() {
        let line = json([
            "type": "queue-operation",
            "timestamp": ts,
            "sessionId": sid,
            "operation": "enqueue"
        ])

        let event = JSONLParser.parse(line: line)

        guard case .queueOperation(let op, _, let sessId) = event else {
            XCTFail("Expected .queueOperation, got \(event)")
            return
        }

        XCTAssertEqual(op, "enqueue")
        XCTAssertEqual(sessId, sid)
    }

    // MARK: - 5. testParseUserEvent

    func testParseUserEvent() {
        let line = json([
            "type": "user",
            "timestamp": ts,
            "sessionId": sid
        ])

        let event = JSONLParser.parse(line: line)

        guard case .user(let date, let sessId) = event else {
            XCTFail("Expected .user, got \(event)")
            return
        }

        XCTAssertNotNil(date)
        XCTAssertEqual(sessId, sid)
    }

    // MARK: - 6. testParseMalformedLine

    func testParseMalformedLine() {
        let event = JSONLParser.parse(line: "this is not json at all {{{")

        guard case .unknown = event else {
            XCTFail("Expected .unknown for malformed line, got \(event)")
            return
        }
    }

    // MARK: - 7. testParseUnknownType

    func testParseUnknownType() {
        let line = json([
            "type": "file-history-snapshot",
            "timestamp": ts,
            "sessionId": sid
        ])

        let event = JSONLParser.parse(line: line)

        guard case .unknown = event else {
            XCTFail("Expected .unknown for unrecognized type, got \(event)")
            return
        }
    }

    // MARK: - 8. testParseAssistantWithoutThinking

    func testParseAssistantWithoutThinking() {
        let line = json([
            "type": "assistant",
            "timestamp": ts,
            "sessionId": sid,
            "message": [
                "model": "claude-haiku-4-5",
                "usage": [
                    "input_tokens": 500,
                    "output_tokens": 100,
                    "cache_read_input_tokens": 0,
                    "cache_creation_input_tokens": 0
                ],
                "content": [
                    ["type": "text", "text": "Quick reply."]
                ]
            ] as [String: Any]
        ])

        let event = JSONLParser.parse(line: line)

        guard case .assistant(let msg, _, _) = event else {
            XCTFail("Expected .assistant, got \(event)")
            return
        }

        XCTAssertNil(msg.thinkingText)
        XCTAssertEqual(msg.outputText, "Quick reply.")
        XCTAssertEqual(msg.model, "claude-haiku-4-5")
    }
}
