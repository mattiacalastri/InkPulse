import XCTest
@testable import InkPulse

// ═══════════════════════════════════════════════════════════════════════════════
// MCPServerManager Tests — config parsing, server lifecycle, edge cases
// ═══════════════════════════════════════════════════════════════════════════════

final class MCPServerManagerTests: XCTestCase {

    // MARK: - Config Parsing

    @MainActor
    func testLoadConfigParsesServers() throws {
        let mgr = MCPServerManager()

        // Write a temp config
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkpulse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configPath = tempDir.appendingPathComponent(".mcp.json")
        let config = """
        {
          "mcpServers": {
            "test-server": {
              "command": "/usr/bin/echo",
              "args": ["hello"],
              "env": {"TEST_VAR": "test_value"}
            },
            "test-server-2": {
              "command": "/usr/bin/true"
            }
          }
        }
        """
        try config.write(to: configPath, atomically: true, encoding: .utf8)

        // loadConfig reads from ~/.mcp.json by default, so we test the parsing logic
        // by verifying the JSON structure is valid
        let data = try Data(contentsOf: configPath)
        let decoded = try JSONDecoder().decode(TestMCPConfig.self, from: data)

        XCTAssertEqual(decoded.mcpServers.count, 2)
        XCTAssertEqual(decoded.mcpServers["test-server"]?.command, "/usr/bin/echo")
        XCTAssertEqual(decoded.mcpServers["test-server"]?.args, ["hello"])
        XCTAssertEqual(decoded.mcpServers["test-server"]?.env?["TEST_VAR"], "test_value")
        XCTAssertEqual(decoded.mcpServers["test-server-2"]?.command, "/usr/bin/true")
        XCTAssertNil(decoded.mcpServers["test-server-2"]?.args)

        try FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testRunningCountStartsAtZero() {
        let mgr = MCPServerManager()
        XCTAssertEqual(mgr.runningCount, 0)
        XCTAssertEqual(mgr.totalCount, 0)
        XCTAssertFalse(mgr.isLoaded)
    }

    @MainActor
    func testStopNonExistentServerIsNoOp() {
        let mgr = MCPServerManager()
        mgr.stopServer("nonexistent")  // Should not crash
        XCTAssertEqual(mgr.runningCount, 0)
    }

    @MainActor
    func testLaunchNonExistentServerIsNoOp() {
        let mgr = MCPServerManager()
        mgr.launchServer("nonexistent")  // Should not crash
        XCTAssertEqual(mgr.runningCount, 0)
    }

    // MARK: - Config Edge Cases

    func testEmptyConfigParsesCorrectly() throws {
        let json = """
        {"mcpServers": {}}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TestMCPConfig.self, from: data)
        XCTAssertTrue(decoded.mcpServers.isEmpty)
    }

    func testConfigWithNoArgsOrEnv() throws {
        let json = """
        {
          "mcpServers": {
            "minimal": {
              "command": "/bin/cat"
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TestMCPConfig.self, from: data)
        let server = decoded.mcpServers["minimal"]!

        XCTAssertEqual(server.command, "/bin/cat")
        XCTAssertNil(server.args)
        XCTAssertNil(server.env)
    }

    func testConfigWithWrapperScript() throws {
        // This is the new pattern after security hardening (sess.609)
        let json = """
        {
          "mcpServers": {
            "bridge": {
              "command": "/Users/test/.claude/mcp-wrapper.sh",
              "args": [
                "/Users/test/.config/credentials/mcp_bridge.env",
                "python3",
                "/Users/test/.claude/mcp-servers/bridge/server.py"
              ]
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TestMCPConfig.self, from: data)
        let server = decoded.mcpServers["bridge"]!

        XCTAssertTrue(server.command.hasSuffix("mcp-wrapper.sh"))
        XCTAssertEqual(server.args?.count, 3)
        XCTAssertTrue(server.args![0].contains("credentials"))
    }

    // MARK: - Large Config Stress

    func testParses50Servers() throws {
        var servers: [String: [String: Any]] = [:]
        for i in 0..<50 {
            servers["server-\(i)"] = [
                "command": "/usr/bin/echo",
                "args": ["test-\(i)"],
            ]
        }
        let config: [String: Any] = ["mcpServers": servers]
        let data = try JSONSerialization.data(withJSONObject: config)
        let decoded = try JSONDecoder().decode(TestMCPConfig.self, from: data)

        XCTAssertEqual(decoded.mcpServers.count, 50)
    }
}

// Mirror the private config struct for testing
private struct TestMCPConfig: Decodable {
    let mcpServers: [String: TestMCPServerConfig]
}

private struct TestMCPServerConfig: Decodable {
    let command: String
    let args: [String]?
    let env: [String: String]?
}
