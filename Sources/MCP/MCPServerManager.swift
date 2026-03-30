import Foundation

/// Manages a pool of shared MCP server processes.
/// Reads ~/.mcp.json, launches each server once, and maintains stdio pipes.
@MainActor
final class MCPServerManager: ObservableObject {

    struct ServerInfo: Identifiable {
        let id: String          // server name from config
        let command: String
        let args: [String]
        let env: [String: String]
        var process: Process?
        var stdin: Pipe?
        var stdout: Pipe?
        var isRunning: Bool { process?.isRunning ?? false }
    }

    @Published private(set) var servers: [String: ServerInfo] = [:]
    @Published private(set) var isLoaded = false

    private let configPath: URL

    init() {
        self.configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcp.json")
    }

    // MARK: - Load Config

    /// Parse ~/.mcp.json and register servers (does NOT launch them).
    func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            log("MCPHub: no .mcp.json found at \(configPath.path)")
            return
        }

        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(MCPConfigFile.self, from: data)

            for (name, server) in config.mcpServers {
                let info = ServerInfo(
                    id: name,
                    command: server.command,
                    args: server.args ?? [],
                    env: server.env ?? [:],
                    process: nil,
                    stdin: nil,
                    stdout: nil
                )
                servers[name] = info
            }

            isLoaded = true
            log("MCPHub: loaded \(servers.count) server configs")
        } catch {
            log("MCPHub: failed to parse .mcp.json: \(error)")
        }
    }

    // MARK: - Launch All

    /// Launch all registered servers that are not already running.
    func launchAll() {
        for name in servers.keys {
            launchServer(name)
        }
    }

    /// Launch a single server by name.
    func launchServer(_ name: String) {
        guard var info = servers[name] else { return }
        guard !info.isRunning else {
            log("MCPHub: \(name) already running")
            return
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: info.command)
        process.arguments = info.args
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Merge server env with current process env
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in info.env {
            environment[k] = v
        }
        process.environment = environment

        // Handle termination
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleTermination(name: name, exitCode: proc.terminationStatus)
            }
        }

        do {
            try process.run()
            info.process = process
            info.stdin = stdinPipe
            info.stdout = stdoutPipe
            servers[name] = info
            log("MCPHub: launched \(name) (PID \(process.processIdentifier))")
        } catch {
            log("MCPHub: failed to launch \(name): \(error)")
        }
    }

    // MARK: - Stop

    func stopAll() {
        for name in servers.keys {
            stopServer(name)
        }
    }

    func stopServer(_ name: String) {
        guard var info = servers[name], info.isRunning else { return }
        info.process?.terminate()
        info.process = nil
        info.stdin = nil
        info.stdout = nil
        servers[name] = info
        log("MCPHub: stopped \(name)")
    }

    // MARK: - Send / Receive

    /// Send a JSON-RPC message to a server's stdin.
    func send(_ name: String, data: Data) {
        guard let info = servers[name], info.isRunning,
              let stdinHandle = info.stdin?.fileHandleForWriting else {
            log("MCPHub: cannot send to \(name) — not running")
            return
        }

        // MCP protocol: Content-Length header + \r\n\r\n + JSON body
        let header = "Content-Length: \(data.count)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            stdinHandle.write(headerData)
            stdinHandle.write(data)
        }
    }

    /// Read available data from a server's stdout (non-blocking peek).
    func readAvailable(_ name: String) -> Data? {
        guard let info = servers[name], info.isRunning,
              let stdoutHandle = info.stdout?.fileHandleForReading else {
            return nil
        }
        let data = stdoutHandle.availableData
        return data.isEmpty ? nil : data
    }

    // MARK: - Status

    var runningCount: Int {
        servers.values.filter(\.isRunning).count
    }

    var totalCount: Int {
        servers.count
    }

    // MARK: - Private

    private func handleTermination(name: String, exitCode: Int32) {
        log("MCPHub: \(name) terminated with exit code \(exitCode)")
        if var info = servers[name] {
            info.process = nil
            info.stdin = nil
            info.stdout = nil
            servers[name] = info
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - Config File Model

private struct MCPConfigFile: Decodable {
    let mcpServers: [String: MCPServerConfig]
}

private struct MCPServerConfig: Decodable {
    let command: String
    let args: [String]?
    let env: [String: String]?
}
