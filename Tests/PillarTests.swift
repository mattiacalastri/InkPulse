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
}
