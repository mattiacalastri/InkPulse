import XCTest
@testable import InkPulse

final class MetricsTests: XCTestCase {

    // MARK: - Helpers

    private let sid = "sess-metrics-001"
    private let baseDate = ISO8601DateFormatter().date(from: "2026-03-23T10:00:00Z")!

    private func makeAssistantEvent(
        model: String = "claude-sonnet-4",
        inputTokens: Int = 100,
        outputTokens: Int = 100,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        thinkingText: String? = nil,
        outputText: String? = nil,
        at offset: TimeInterval = 0
    ) -> ClaudeEvent {
        let usage = TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadInputTokens: cacheRead,
            cacheCreationInputTokens: cacheCreation
        )
        let msg = AssistantMessage(
            model: model,
            usage: usage,
            thinkingText: thinkingText,
            outputText: outputText,
            requestId: nil,
            toolUses: []
        )
        return .assistant(msg, timestamp: baseDate.addingTimeInterval(offset), sessionId: sid)
    }

    private func makeToolEvent(isError: Bool = false, at offset: TimeInterval = 0) -> ClaudeEvent {
        .progress(
            toolUseID: "tool-\(UUID().uuidString.prefix(4))",
            toolName: "Bash",
            isToolUse: true,
            isError: isError,
            timestamp: baseDate.addingTimeInterval(offset),
            sessionId: sid
        )
    }

    private func makeQueueEvent(operation: String, at offset: TimeInterval = 0) -> ClaudeEvent {
        .queueOperation(
            operation: operation,
            timestamp: baseDate.addingTimeInterval(offset),
            sessionId: sid
        )
    }

    // MARK: - 1. testTokenMinCalculation

    func testTokenMinCalculation() {
        let session = SessionMetrics(sessionId: sid, startTime: baseDate)

        // Inject 1000 output tokens spread across 60 seconds
        session.ingest(makeAssistantEvent(outputTokens: 500, at: 10))
        session.ingest(makeAssistantEvent(outputTokens: 500, at: 50))

        let snap = session.snapshot(at: baseDate.addingTimeInterval(60))

        // 1000 tokens in 60s window = 1000 tok/min
        XCTAssertGreaterThan(snap.tokenMin, 500, "Expected >500 tok/min, got \(snap.tokenMin)")
    }

    // MARK: - 2. testCacheHitIncludesAllInputs

    func testCacheHitIncludesAllInputs() {
        let session = SessionMetrics(sessionId: sid, startTime: baseDate)

        // 100 input + 10 cache_read + 10 cache_creation = 120 denominator
        // cacheHit = 10 / 120
        session.ingest(makeAssistantEvent(
            inputTokens: 100,
            outputTokens: 50,
            cacheRead: 10,
            cacheCreation: 10,
            at: 5
        ))

        let snap = session.snapshot(at: baseDate.addingTimeInterval(10))
        let expected = 10.0 / 120.0

        XCTAssertEqual(snap.cacheHit, expected, accuracy: 0.001,
                       "Expected cacheHit ~\(expected), got \(snap.cacheHit)")
    }

    // MARK: - 3. testErrorRateCalculation

    func testErrorRateCalculation() {
        let session = SessionMetrics(sessionId: sid, startTime: baseDate)

        // 3 tool events, 1 is an error → errorRate = 1/3
        session.ingest(makeToolEvent(isError: false, at: 5))
        session.ingest(makeToolEvent(isError: true, at: 10))
        session.ingest(makeToolEvent(isError: false, at: 15))

        let snap = session.snapshot(at: baseDate.addingTimeInterval(20))

        XCTAssertEqual(snap.errorRate, 1.0 / 3.0, accuracy: 0.01,
                       "Expected errorRate ~0.333, got \(snap.errorRate)")
    }

    // MARK: - 4. testSubagentTracking

    func testSubagentTracking() {
        let session = SessionMetrics(sessionId: sid, startTime: baseDate)

        // Subagents are now tracked via Agent tool uses in assistant messages
        session.ingest(makeAssistantEventWithAgentTool(at: 5))
        session.ingest(makeAssistantEventWithAgentTool(at: 10))

        let snap = session.snapshot(at: baseDate.addingTimeInterval(20))

        XCTAssertEqual(snap.subagentCount, 2,
                       "Expected 2 subagents (2 Agent tool uses), got \(snap.subagentCount)")
    }

    private func makeAssistantEventWithAgentTool(at offset: TimeInterval) -> ClaudeEvent {
        let agentTool = ToolUseInfo(
            id: "tool-\(UUID().uuidString.prefix(4))",
            name: "Agent",
            target: "subagent-task",
            fullPath: nil,
            subject: nil
        )
        let usage = TokenUsage(
            inputTokens: 100,
            outputTokens: 50,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0
        )
        let msg = AssistantMessage(
            model: "claude-sonnet-4",
            usage: usage,
            thinkingText: nil,
            outputText: "spawning agent",
            requestId: nil,
            toolUses: [agentTool]
        )
        return .assistant(msg, timestamp: baseDate.addingTimeInterval(offset), sessionId: sid)
    }

    // MARK: - 5. testCostCalculation

    func testCostCalculation() {
        let session = SessionMetrics(sessionId: sid, startTime: baseDate)

        // 1M input + 100K output on opus
        // Input: 1_000_000 / 1_000_000 * 5.0 = $5.0
        // Output: 100_000 / 1_000_000 * 25.0 = $2.5
        // Total USD: $7.5 → EUR: 7.5 * 0.91 = 6.825
        session.ingest(makeAssistantEvent(
            model: "claude-opus-4",
            inputTokens: 1_000_000,
            outputTokens: 100_000,
            at: 5
        ))

        let snap = session.snapshot(at: baseDate.addingTimeInterval(10))

        XCTAssertEqual(snap.costEUR, 6.825, accuracy: 0.1,
                       "Expected ~EUR 6.825, got \(snap.costEUR)")
    }
}
