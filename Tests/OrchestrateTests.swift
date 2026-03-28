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

    func testDecodeMissionsFileMalformed() {
        let json = """
        {"not": "a missions file"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(MissionsFile.self, from: json))
    }
}
