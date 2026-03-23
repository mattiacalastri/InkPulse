import XCTest
@testable import InkPulse

final class HealthScoreTests: XCTestCase {

    // MARK: - 1. testPerfectHealth

    func testPerfectHealth() {
        let result = HealthScore.compute(
            tokenMin: 600,
            toolFreq: 5.0,
            idleAvgS: 1.0,
            errorRate: 0.01,
            thinkOutputRatio: 1.0,
            cacheHit: 0.70,
            subagentCount: 1,
            costEUR: 0.50,
            sessionDurationMinutes: 30.0
        )

        XCTAssertGreaterThan(result.score, 85,
                             "Perfect metrics should yield >85, got \(result.score)")
        XCTAssertNil(result.anomaly,
                     "Perfect metrics should have no anomaly, got \(String(describing: result.anomaly))")
    }

    // MARK: - 2. testCriticalHealth

    func testCriticalHealth() {
        let result = HealthScore.compute(
            tokenMin: 5,
            toolFreq: 0.0,
            idleAvgS: 35.0,
            errorRate: 0.35,
            thinkOutputRatio: 10.0,
            cacheHit: 0.05,
            subagentCount: 10,
            costEUR: 50.0,
            sessionDurationMinutes: 5.0
        )

        XCTAssertLessThan(result.score, 20,
                          "Critical metrics should yield <20, got \(result.score)")
    }

    // MARK: - 3. testDeepThinkingAnomaly

    func testDeepThinkingAnomaly() {
        let result = HealthScore.compute(
            tokenMin: 300,
            toolFreq: 3.0,
            idleAvgS: 2.0,
            errorRate: 0.01,
            thinkOutputRatio: 8.0,
            cacheHit: 0.50,
            subagentCount: 0,
            costEUR: 1.0,
            sessionDurationMinutes: 10.0
        )

        XCTAssertEqual(result.anomaly, .deepThinking,
                       "Expected deepThinking anomaly, got \(String(describing: result.anomaly))")
    }

    // MARK: - 4. testStallAnomaly

    func testStallAnomaly() {
        let result = HealthScore.compute(
            tokenMin: 0,
            toolFreq: 0.0,
            idleAvgS: 45.0,
            errorRate: 0.0,
            thinkOutputRatio: nil,
            cacheHit: 0.50,
            subagentCount: 0,
            costEUR: 0.10,
            sessionDurationMinutes: 10.0
        )

        XCTAssertEqual(result.anomaly, .stall,
                       "Expected stall anomaly, got \(String(describing: result.anomaly))")
    }

    // MARK: - 5. testLoopAnomaly

    func testLoopAnomaly() {
        let result = HealthScore.compute(
            tokenMin: 500,
            toolFreq: 18.0,
            idleAvgS: 1.0,
            errorRate: 0.35,
            thinkOutputRatio: nil,
            cacheHit: 0.50,
            subagentCount: 0,
            costEUR: 1.0,
            sessionDurationMinutes: 10.0
        )

        XCTAssertEqual(result.anomaly, .loop,
                       "Expected loop anomaly, got \(String(describing: result.anomaly))")
    }

    // MARK: - 6. testNilThinkOutputRedistributesWeight

    func testNilThinkOutputRedistributesWeight() {
        // With thinkOutputRatio
        let withRatio = HealthScore.compute(
            tokenMin: 400,
            toolFreq: 5.0,
            idleAvgS: 3.0,
            errorRate: 0.03,
            thinkOutputRatio: 1.5,
            cacheHit: 0.55,
            subagentCount: 1,
            costEUR: 0.50,
            sessionDurationMinutes: 15.0
        )

        // Without thinkOutputRatio (nil)
        let withoutRatio = HealthScore.compute(
            tokenMin: 400,
            toolFreq: 5.0,
            idleAvgS: 3.0,
            errorRate: 0.03,
            thinkOutputRatio: nil,
            cacheHit: 0.55,
            subagentCount: 1,
            costEUR: 0.50,
            sessionDurationMinutes: 15.0
        )

        // Both should produce reasonable scores >50
        XCTAssertGreaterThan(withRatio.score, 50,
                             "With ratio should be >50, got \(withRatio.score)")
        XCTAssertGreaterThan(withoutRatio.score, 50,
                             "Without ratio should be >50, got \(withoutRatio.score)")
    }

    // MARK: - 7. testToolFreqBellCurve

    func testToolFreqBellCurve() {
        let center = HealthScore.scoreToolFreqBellCurve(freq: 5.0)
        let extreme = HealthScore.scoreToolFreqBellCurve(freq: 0.0)

        XCTAssertGreaterThan(center, extreme,
                             "Center(5) = \(center) should score higher than extreme(0) = \(extreme)")
        XCTAssertEqual(center, 1.0, accuracy: 0.001,
                       "Freq=5 should score 1.0, got \(center)")
        XCTAssertEqual(extreme, 0.0, accuracy: 0.001,
                       "Freq=0 should score 0.0, got \(extreme)")
    }
}
