import XCTest
@testable import InkPulse

final class TaskNameTests: XCTestCase {

    func testToolUseInfoHasSubject() {
        let info = ToolUseInfo(id: "t1", name: "TaskCreate", target: nil, fullPath: nil, subject: "Fix OAuth")
        XCTAssertEqual(info.subject, "Fix OAuth")
    }

    func testToolUseInfoNonTaskHasNilSubject() {
        let info = ToolUseInfo(id: "t2", name: "Edit", target: "config.swift", fullPath: nil, subject: nil)
        XCTAssertNil(info.subject)
    }

    func testParseTaskCreateFromJSONL() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-03-25T10:00:00.000Z","sessionId":"test-123","message":{"model":"claude-opus-4-6","content":[{"type":"tool_use","id":"toolu_abc","name":"TaskCreate","input":{"subject":"Deploy Railway","description":"test"}}],"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
        let event = JSONLParser.parse(line: jsonl)
        guard case .assistant(let msg, _, _) = event else {
            XCTFail("Expected assistant event"); return
        }
        XCTAssertEqual(msg.toolUses.count, 1)
        XCTAssertEqual(msg.toolUses[0].name, "TaskCreate")
        XCTAssertEqual(msg.toolUses[0].subject, "Deploy Railway")
    }

    func testParseNonTaskToolHasNilSubject() {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-03-25T10:00:00.000Z","sessionId":"test-123","message":{"model":"claude-opus-4-6","content":[{"type":"tool_use","id":"toolu_abc","name":"Edit","input":{"file_path":"/tmp/test.swift","old_string":"a","new_string":"b"}}],"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
        let event = JSONLParser.parse(line: jsonl)
        guard case .assistant(let msg, _, _) = event else {
            XCTFail("Expected assistant event"); return
        }
        XCTAssertNil(msg.toolUses[0].subject)
    }

    func testSessionMetricsIngestsTaskName() {
        let metrics = SessionMetrics(sessionId: "test", startTime: Date())
        let msg = AssistantMessage(
            model: "claude-opus-4-6",
            usage: TokenUsage(inputTokens: 100, outputTokens: 50, cacheReadInputTokens: 0, cacheCreationInputTokens: 0),
            thinkingText: nil,
            outputText: nil,
            requestId: nil,
            toolUses: [ToolUseInfo(id: "t1", name: "TaskCreate", target: nil, fullPath: nil, subject: "Fix OAuth")]
        )
        let event = ClaudeEvent.assistant(msg, timestamp: Date(), sessionId: "test")
        metrics.ingest(event)
        XCTAssertEqual(metrics.activeTaskName, "Fix OAuth")
    }

    func testSessionMetricsIgnoresNonTaskTools() {
        let metrics = SessionMetrics(sessionId: "test", startTime: Date())
        let msg = AssistantMessage(
            model: "claude-opus-4-6",
            usage: TokenUsage(inputTokens: 100, outputTokens: 50, cacheReadInputTokens: 0, cacheCreationInputTokens: 0),
            thinkingText: nil,
            outputText: nil,
            requestId: nil,
            toolUses: [ToolUseInfo(id: "t1", name: "Edit", target: "test.swift", fullPath: nil, subject: nil)]
        )
        let event = ClaudeEvent.assistant(msg, timestamp: Date(), sessionId: "test")
        metrics.ingest(event)
        XCTAssertNil(metrics.activeTaskName)
    }
}
