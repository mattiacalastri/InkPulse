import XCTest
@testable import InkPulse

final class EGITests: XCTestCase {

    // MARK: - Helpers

    private let sid = "sess-egi-001"
    private let baseDate = ISO8601DateFormatter().date(from: "2026-03-24T10:00:00Z")!

    private func makeAssistantEvent(
        model: String = "claude-opus-4",
        inputTokens: Int = 100,
        outputTokens: Int = 500,
        cacheRead: Int = 800,
        cacheCreation: Int = 0,
        thinkingText: String? = String(repeating: "x", count: 400),
        outputText: String? = String(repeating: "y", count: 200),
        toolUses: [ToolUseInfo] = [],
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
            toolUses: toolUses
        )
        return .assistant(msg, timestamp: baseDate.addingTimeInterval(offset), sessionId: sid)
    }

    private func makeToolEvent(name: String = "Read", isError: Bool = false, at offset: TimeInterval = 0) -> ClaudeEvent {
        .progress(
            toolUseID: "tool-\(UUID().uuidString.prefix(4))",
            toolName: name,
            isToolUse: true,
            isError: isError,
            timestamp: baseDate.addingTimeInterval(offset),
            sessionId: sid
        )
    }

    // MARK: - 1. EGI Domain Classification

    func testDomainClassification() {
        XCTAssertEqual(EGIDomain.classify("Read"), .code)
        XCTAssertEqual(EGIDomain.classify("Edit"), .code)
        XCTAssertEqual(EGIDomain.classify("Bash"), .code)
        XCTAssertEqual(EGIDomain.classify("mcp__obsidian__read_note"), .knowledge)
        XCTAssertEqual(EGIDomain.classify("mcp__gmail__search"), .communication)
        XCTAssertEqual(EGIDomain.classify("mcp__telegram__SEND_MESSAGE"), .communication)
        XCTAssertEqual(EGIDomain.classify("mcp__railway__deployment_status"), .infrastructure)
        XCTAssertEqual(EGIDomain.classify("mcp__github__list_commits"), .infrastructure)
        XCTAssertEqual(EGIDomain.classify("mcp__fal__generate_image"), .creation)
        XCTAssertEqual(EGIDomain.classify("mcp__cloudinary__upload-asset"), .creation)
        XCTAssertEqual(EGIDomain.classify("mcp__stripe__list_customers"), .business)
        XCTAssertEqual(EGIDomain.classify("mcp__n8n__list_workflows"), .business)
        XCTAssertEqual(EGIDomain.classify("mcp__ghl__ghl_search_contacts"), .business)
        XCTAssertEqual(EGIDomain.classify("mcp__x__post_tweet"), .communication)
        XCTAssertEqual(EGIDomain.classify("mcp__linkedin__publish_post"), .communication)
    }

    // MARK: - 2. EGI Signals Pass Count

    func testSignalsAllPass() {
        let signals = EGISignals(
            velocity: true,
            accuracy: true,
            context: true,
            diversity: true,
            crossDomain: true,
            flow: true,
            balance: true
        )
        XCTAssertEqual(signals.passCount, 7)
    }

    func testSignalsNonePass() {
        let signals = EGISignals(
            velocity: false,
            accuracy: false,
            context: false,
            diversity: false,
            crossDomain: false,
            flow: false,
            balance: false
        )
        XCTAssertEqual(signals.passCount, 0)
    }

    // MARK: - 3. EGI Confidence

    func testConfidenceHighWhenAllGood() {
        let conf = EGISignals.confidence(
            tokenMin: 600,
            errorRate: 0.0,
            cacheHit: 0.90,
            toolDiversity: 6,
            domainSpread: 4,
            idleAvgS: 2.0,
            thinkOutputRatio: 1.5
        )
        XCTAssertGreaterThan(conf, 0.85, "Expected high confidence, got \(conf)")
    }

    func testConfidenceLowWhenAllBad() {
        let conf = EGISignals.confidence(
            tokenMin: 0,
            errorRate: 0.10,
            cacheHit: 0.0,
            toolDiversity: 0,
            domainSpread: 0,
            idleAvgS: 30.0,
            thinkOutputRatio: nil
        )
        XCTAssertLessThan(conf, 0.30, "Expected low confidence, got \(conf)")
    }

    // MARK: - 4. EGI State Machine — Dormant to Stirring

    func testDormantToStirring() {
        let tracker = EGITracker()

        // Feed 20s of signals with passCount >= 4 (sustained 15s threshold)
        for i in stride(from: 0, to: 20, by: 1) {
            let time = baseDate.addingTimeInterval(Double(i))
            let result = tracker.evaluate(
                tokenMin: 400,      // velocity ✓
                errorRate: 0.01,    // accuracy ✓
                cacheHit: 0.80,     // context ✓
                toolDiversity: 5,   // diversity ✓
                domainSpread: 3,    // crossDomain ✓
                idleAvgS: 5,        // flow ✓
                thinkOutputRatio: 1.0, // balance ✓
                subagentCount: 0,
                at: time
            )

            if i >= 16 {
                // After 15s sustained above 4, should transition
                XCTAssertGreaterThanOrEqual(result.state.level, EGIState.stirring.level,
                    "Expected at least stirring at t=\(i), got \(result.state)")
            }
        }
    }

    // MARK: - 5. EGI State Machine — Full Ascent to Peak

    func testFullAscentToPeak() {
        let tracker = EGITracker()

        // Run 120s of perfect signals — should reach peak
        var lastState: EGIState = .dormant
        var reachedStirring = false
        var reachedOpen = false
        var reachedPeak = false

        for i in stride(from: 0, to: 120, by: 1) {
            let time = baseDate.addingTimeInterval(Double(i))
            let result = tracker.evaluate(
                tokenMin: 800,
                errorRate: 0.005,
                cacheHit: 0.95,
                toolDiversity: 7,
                domainSpread: 4,
                idleAvgS: 3,
                thinkOutputRatio: 1.2,
                subagentCount: 2,
                at: time
            )

            if result.state == .stirring { reachedStirring = true }
            if result.state == .open { reachedOpen = true }
            if result.state == .peak { reachedPeak = true }
            lastState = result.state
        }

        XCTAssertTrue(reachedStirring, "Should have reached stirring")
        XCTAssertTrue(reachedOpen, "Should have reached open")
        XCTAssertTrue(reachedPeak, "Should have reached peak")
        XCTAssertEqual(lastState, .peak, "Final state should be peak")
    }

    // MARK: - 6. EGI State Machine — Decay on Bad Signals

    func testDecayFromStirring() {
        let tracker = EGITracker()

        // Build up to stirring (20s of good signals)
        for i in 0..<20 {
            let _ = tracker.evaluate(
                tokenMin: 500, errorRate: 0.01, cacheHit: 0.80,
                toolDiversity: 5, domainSpread: 3, idleAvgS: 4,
                thinkOutputRatio: 1.0, subagentCount: 0,
                at: baseDate.addingTimeInterval(Double(i))
            )
        }

        // Now feed bad signals for 60s — should decay back to dormant
        // (hysteresis requires sustained below for 20s + timeSinceTransition > 10s)
        var decayed = false
        for i in 20..<80 {
            let result = tracker.evaluate(
                tokenMin: 10,       // velocity ✗
                errorRate: 0.15,    // accuracy ✗
                cacheHit: 0.10,     // context ✗
                toolDiversity: 1,   // diversity ✗
                domainSpread: 1,    // crossDomain ✗
                idleAvgS: 25,       // flow ✗
                thinkOutputRatio: nil, // balance neutral
                subagentCount: 0,
                at: baseDate.addingTimeInterval(Double(i))
            )
            if result.state == .dormant { decayed = true }
        }

        XCTAssertTrue(decayed, "Should have decayed back to dormant after bad signals")
    }

    // MARK: - 7. EGI Hysteresis — No Flapping

    func testNoRapidFlapping() {
        let tracker = EGITracker()

        // Build to stirring
        for i in 0..<20 {
            let _ = tracker.evaluate(
                tokenMin: 500, errorRate: 0.01, cacheHit: 0.80,
                toolDiversity: 5, domainSpread: 3, idleAvgS: 4,
                thinkOutputRatio: 1.0, subagentCount: 0,
                at: baseDate.addingTimeInterval(Double(i))
            )
        }

        // Brief dip (5s) — should NOT decay due to hysteresis (needs 20s sustained below)
        var states: [EGIState] = []
        for i in 20..<25 {
            let result = tracker.evaluate(
                tokenMin: 50, errorRate: 0.08, cacheHit: 0.20,
                toolDiversity: 1, domainSpread: 1, idleAvgS: 20,
                thinkOutputRatio: nil, subagentCount: 0,
                at: baseDate.addingTimeInterval(Double(i))
            )
            states.append(result.state)
        }

        // Should still be stirring — brief dip shouldn't cause flapping
        let stillStirring = states.contains(where: { $0 >= .stirring })
        XCTAssertTrue(stillStirring, "Brief dip should not cause immediate decay: \(states)")
    }

    // MARK: - 8. Context Window % Calculation

    func testContextWindowPercent() {
        let session = SessionMetrics(sessionId: sid, startTime: baseDate)

        // Simulate 150K context usage on a 200K model
        session.ingest(makeAssistantEvent(
            model: "claude-opus-4",
            inputTokens: 3,
            outputTokens: 37,
            cacheRead: 149000,
            cacheCreation: 997,
            at: 5
        ))

        let snap = session.snapshot(at: baseDate.addingTimeInterval(10))

        // lastContextTokens = 3 + 149000 + 997 = 150000
        XCTAssertEqual(snap.lastContextTokens, 150000,
            "Expected 150000 context tokens, got \(snap.lastContextTokens)")

        // contextPercent = 150000 / 200000 = 0.75
        XCTAssertEqual(snap.contextPercent, 0.75, accuracy: 0.01,
            "Expected ~0.75 context ratio, got \(snap.contextPercent)")
    }

    // MARK: - 9. Last Tool Name Tracking

    func testLastToolNameTracking() {
        let session = SessionMetrics(sessionId: sid, startTime: baseDate)

        let tools = [
            ToolUseInfo(id: "t1", name: "Read", target: "AppState.swift"),
            ToolUseInfo(id: "t2", name: "Edit", target: "LiveTab.swift")
        ]

        session.ingest(makeAssistantEvent(toolUses: tools, at: 5))

        let snap = session.snapshot(at: baseDate.addingTimeInterval(10))

        XCTAssertEqual(snap.lastToolName, "Edit", "Expected last tool 'Edit', got \(snap.lastToolName ?? "nil")")
        XCTAssertEqual(snap.lastToolTarget, "LiveTab.swift", "Expected target 'LiveTab.swift', got \(snap.lastToolTarget ?? "nil")")
    }
}
