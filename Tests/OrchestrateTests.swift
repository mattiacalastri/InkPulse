import XCTest
@testable import InkPulse

final class OrchestrateTests: XCTestCase {

    func testDecodeMissionsFileValid() throws {
        let json = """
        {
          "generated": "2026-03-28T14:30:00Z",
          "reasoning": "AuraHome needs ads acceleration, Astra has outstanding to collect",
          "missions": [
            {"id": "m1", "name": "AuraHome Ads", "cwd": "~/projects/aurahome", "icon": "flame.fill", "prompt": "Focus on Meta Ads creative volume"},
            {"id": "m2", "name": "Astra Collect", "cwd": "~/Downloads/Astra", "icon": "envelope.fill", "prompt": "Send outstanding reminders"},
            {"id": "m3", "name": "Bot Monitor", "cwd": "~/btc_predictions", "icon": "chart.line.uptrend.xyaxis", "prompt": "Check Phase Engine WR"},
            {"id": "m4", "name": "Brand Deploy", "cwd": "~/claude_voice", "icon": "server.rack", "prompt": "Verify Railway health"},
            {"id": "m5", "name": "Vault Garden", "cwd": "~", "icon": "leaf.fill", "prompt": "Prune orphan notes"},
            {"id": "m6", "name": "Content Wave", "cwd": "~", "icon": "text.bubble.fill", "prompt": "Publish 3 seeds from batch"}
          ]
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(MissionsFile.self, from: json)
        XCTAssertEqual(file.missions.count, 6)
        XCTAssertEqual(file.missions[0].name, "AuraHome Ads")
        XCTAssertEqual(file.missions[0].cwd, "~/projects/aurahome")
        XCTAssertEqual(file.reasoning.contains("AuraHome"), true)
    }

    func testDecodeMissionsFileWithOptionalColor() throws {
        let json = """
        {
          "generated": "2026-03-28T14:30:00Z",
          "reasoning": "Test",
          "missions": [
            {"id": "m1", "name": "Test", "cwd": "~", "icon": "star", "color": "#FF6B35", "prompt": "Test prompt"}
          ]
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(MissionsFile.self, from: json)
        XCTAssertEqual(file.missions[0].color, "#FF6B35")
    }

    func testDecodeMissionsFileMalformed() throws {
        let json = """
        {"not": "a missions file"}
        """.data(using: .utf8)!

        // Flexible decoder degrades gracefully — malformed input yields empty missions, not a throw
        let file = try JSONDecoder().decode(MissionsFile.self, from: json)
        XCTAssertTrue(file.missions.isEmpty)
        XCTAssertTrue(file.reasoning.isEmpty)
    }

    // MARK: - MissionsWatcher

    func testMissionsWatcherReadsFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkpulse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let missionsPath = tmpDir.appendingPathComponent("missions.json")

        let expectation = XCTestExpectation(description: "missions loaded")
        var receivedFile: MissionsFile?

        let watcher = MissionsWatcher(directory: tmpDir) { file in
            receivedFile = file
            expectation.fulfill()
        }
        watcher.start()

        // Write a valid missions file
        let json = """
        {
          "generated": "2026-03-28T14:30:00Z",
          "reasoning": "Test run",
          "missions": [
            {"id": "m1", "name": "Test", "cwd": "~", "icon": "star", "prompt": "Do test"}
          ]
        }
        """.data(using: .utf8)!
        try json.write(to: missionsPath)

        wait(for: [expectation], timeout: 5.0)
        watcher.stop()

        XCTAssertNotNil(receivedFile)
        XCTAssertEqual(receivedFile?.missions.count, 1)
    }
}
