import XCTest
@testable import InkPulse

final class PillarTests: XCTestCase {
    func testKnownPillarBTCBot() {
        let info = PillarInfo.from(cwd: "/Users/mattia/btc_predictions")
        XCTAssertEqual(info.name, "BTC Bot")
        XCTAssertEqual(info.shortName, "BT")
    }
    func testKnownPillarAuraHome() {
        let info = PillarInfo.from(cwd: "/Users/mattia/projects/aurahome")
        XCTAssertEqual(info.name, "AuraHome")
        XCTAssertEqual(info.shortName, "AH")
    }
    func testKnownPillarAstraDigital() {
        let info = PillarInfo.from(cwd: "/Users/mattia/Downloads/Astra Digital Marketing")
        XCTAssertEqual(info.name, "Astra")
        XCTAssertEqual(info.shortName, "AD")
    }
    func testKnownPillarAstraOS() {
        let info = PillarInfo.from(cwd: "/Users/mattia/claude_voice")
        XCTAssertEqual(info.name, "Astra OS")
        XCTAssertEqual(info.shortName, "OS")
    }
    func testKnownPillarInkPulse() {
        let info = PillarInfo.from(cwd: "/Users/mattia/projects/InkPulse")
        XCTAssertEqual(info.name, "InkPulse")
        XCTAssertEqual(info.shortName, "IP")
    }
    func testUnknownDirFallsBack() {
        let info = PillarInfo.from(cwd: "/Users/mattia/projects/my-cool-app")
        XCTAssertEqual(info.name, "My-cool-app")
    }
    func testNilCwdReturnsHome() {
        let info = PillarInfo.from(cwd: nil)
        XCTAssertEqual(info.name, "Home")
    }
    func testHomeDirReturnsHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let info = PillarInfo.from(cwd: home)
        XCTAssertEqual(info.name, "Home")
    }

    // MARK: - Project Inference Tests

    func testInferredProjectOverridesHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let info = PillarInfo.from(cwd: home, inferredProject: "LuxGuard")
        XCTAssertEqual(info.name, "LuxGuard")
        XCTAssertEqual(info.shortName, "LU")
    }

    func testInferredProjectIgnoredWhenCwdIsKnownPillar() {
        let info = PillarInfo.from(cwd: "/Users/mattia/btc_predictions", inferredProject: "SomeProject")
        XCTAssertEqual(info.name, "BTC Bot")
    }

    func testInferredProjectIgnoredWhenCwdIsNotHome() {
        let info = PillarInfo.from(cwd: "/Users/mattia/projects/my-app", inferredProject: "Other")
        XCTAssertEqual(info.name, "My-app")
    }

    func testNilInferredProjectKeepsHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let info = PillarInfo.from(cwd: home, inferredProject: nil)
        XCTAssertEqual(info.name, "Home")
    }

    func testEmptyInferredProjectKeepsHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let info = PillarInfo.from(cwd: home, inferredProject: "")
        XCTAssertEqual(info.name, "Home")
    }

    // MARK: - Smart Capitalize Tests

    func testSmartCapitalizeLowercase() {
        XCTAssertEqual(SessionMetrics.smartCapitalize("luxguard"), "Luxguard")
    }

    func testSmartCapitalizeHyphenated() {
        XCTAssertEqual(SessionMetrics.smartCapitalize("my-project"), "My Project")
    }

    func testSmartCapitalizeUnderscored() {
        XCTAssertEqual(SessionMetrics.smartCapitalize("cool_app"), "Cool App")
    }

    func testSmartCapitalizeAlreadyCapitalized() {
        XCTAssertEqual(SessionMetrics.smartCapitalize("InkPulse"), "InkPulse")
    }

    func testSmartCapitalizeUnicodePrefix() {
        XCTAssertEqual(SessionMetrics.smartCapitalize("\u{26A1} Astra Digital Marketing"), "\u{26A1} Astra Digital Marketing")
    }

    // MARK: - Inference Algorithm Tests

    func testInferenceFromToolPaths() {
        let metrics = SessionMetrics(sessionId: "test", startTime: Date())
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Simulate ingesting events with luxguard file paths
        for i in 0..<5 {
            let event = makeAssistantEvent(
                sessionId: "test",
                filePath: "\(home)/Downloads/clients/luxguard/file\(i).css"
            )
            metrics.ingest(event)
        }

        XCTAssertEqual(metrics.inferredProject, "Luxguard")
    }

    func testInferenceSkipsContainerDirs() {
        let metrics = SessionMetrics(sessionId: "test", startTime: Date())
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        for i in 0..<5 {
            let event = makeAssistantEvent(
                sessionId: "test",
                filePath: "\(home)/projects/footgolfpark/pages/page\(i).html"
            )
            metrics.ingest(event)
        }

        XCTAssertEqual(metrics.inferredProject, "Footgolfpark")
    }

    func testInferenceReturnsNilWithNoPaths() {
        let metrics = SessionMetrics(sessionId: "test", startTime: Date())
        XCTAssertNil(metrics.inferredProject)
    }

    func testInferenceMostFrequentWins() {
        let metrics = SessionMetrics(sessionId: "test", startTime: Date())
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // 4 luxguard paths
        for i in 0..<4 {
            let event = makeAssistantEvent(
                sessionId: "test",
                filePath: "\(home)/projects/luxguard/file\(i).css"
            )
            metrics.ingest(event)
        }
        // 2 footgolf paths
        for i in 0..<2 {
            let event = makeAssistantEvent(
                sessionId: "test",
                filePath: "\(home)/projects/footgolfpark/page\(i).html"
            )
            metrics.ingest(event)
        }

        XCTAssertEqual(metrics.inferredProject, "Luxguard")
    }

    func testInferenceIgnoresHomeDotfiles() {
        let metrics = SessionMetrics(sessionId: "test", startTime: Date())
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        for i in 0..<3 {
            let event = makeAssistantEvent(
                sessionId: "test",
                filePath: "\(home)/.zshrc\(i)"
            )
            metrics.ingest(event)
        }

        XCTAssertNil(metrics.inferredProject)
    }

    // MARK: - Test Helpers

    /// Creates a minimal assistant ClaudeEvent with a single tool_use containing a file_path.
    private func makeAssistantEvent(sessionId: String, filePath: String) -> ClaudeEvent {
        let toolUse = ToolUseInfo(
            id: UUID().uuidString,
            name: "Read",
            target: URL(fileURLWithPath: filePath).lastPathComponent,
            fullPath: filePath,
            subject: nil
        )
        let msg = AssistantMessage(
            model: "claude-opus-4-6",
            usage: TokenUsage(inputTokens: 100, outputTokens: 50, cacheReadInputTokens: 0, cacheCreationInputTokens: 0),
            thinkingText: nil,
            outputText: "test",
            requestId: nil,
            toolUses: [toolUse]
        )
        return .assistant(msg, timestamp: Date(), sessionId: sessionId)
    }
}
