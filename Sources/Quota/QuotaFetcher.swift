import Foundation

/// Fetches real quota data from Anthropic's OAuth usage endpoint.
/// Token is read from macOS Keychain (service: "Claude Code-credentials").
final class QuotaFetcher {

    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let betaHeader = "oauth-2025-04-20"
    private let userAgent = "claude-code/1.0.0"
    private let refreshInterval: TimeInterval = 300  // 5 minutes

    private var timer: Timer?
    private(set) var lastSnapshot: QuotaSnapshot?
    private var onUpdate: ((QuotaSnapshot?) -> Void)?
    private var cachedToken: String?

    // MARK: - Lifecycle

    func start(onUpdate: @escaping (QuotaSnapshot?) -> Void) {
        self.onUpdate = onUpdate
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Fetch

    func fetch() {
        AppState.log("QuotaFetcher: fetching...")
        guard let token = resolveToken() else {
            AppState.log("QuotaFetcher: no OAuth token found")
            onUpdate?(nil)
            return
        }
        AppState.log("QuotaFetcher: token found (\(token.prefix(15))...)")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                AppState.log("QuotaFetcher: request failed — \(error.localizedDescription)")
                DispatchQueue.main.async { self.onUpdate?(nil) }
                return
            }

            guard let data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                AppState.log("QuotaFetcher: HTTP \(code)")
                DispatchQueue.main.async { self.onUpdate?(nil) }
                return
            }

            if let raw = String(data: data, encoding: .utf8) {
                AppState.log("QuotaFetcher: raw response — \(String(raw.prefix(500)))")
            }
            let snapshot = self.parse(data)
            if let s = snapshot {
                let fh = s.fiveHour.map { "5h: \($0.utilization)% used" } ?? "nil"
                let sd = s.sevenDay.map { "7d: \($0.utilization)% used" } ?? "nil"
                AppState.log("QuotaFetcher: \(s.plan.rawValue) | \(fh) | \(sd)")
            } else {
                AppState.log("QuotaFetcher: parse returned nil")
            }
            DispatchQueue.main.async {
                self.lastSnapshot = snapshot
                self.onUpdate?(snapshot)
            }
        }.resume()
    }

    // MARK: - Token Resolution

    /// Keychain backoff: avoid re-prompting after failures.
    private var keychainBackoffUntil: Date?

    /// Reads the OAuth access token from file first, then macOS Keychain.
    private func resolveToken() -> String? {
        if let cached = cachedToken { return cached }

        // 1. Try file-based credentials (legacy, no prompt risk)
        if let fileToken = readFromFile() {
            cachedToken = fileToken
            return fileToken
        }

        // 2. Try macOS Keychain via /usr/bin/security (same as claude-hud)
        if let keychainToken = readFromKeychain() {
            cachedToken = keychainToken
            return keychainToken
        }

        AppState.log("QuotaFetcher: no token found (file or Keychain)")
        return nil
    }

    private func readFromFile() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent(".claude/.credentials.json"),
            home.appendingPathComponent(".claude/credentials.json")
        ]
        for path in paths {
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // Claude Code 2.x nested format
            if let oauth = json["claudeAiOauth"] as? [String: Any],
               let token = oauth["accessToken"] as? String, !token.isEmpty {
                return token
            }
            // Flat format
            if let token = json["accessToken"] as? String ?? json["access_token"] as? String, !token.isEmpty {
                return token
            }
        }
        return nil
    }

    /// Read OAuth token from macOS Keychain using /usr/bin/security.
    /// Uses absolute path to avoid PATH hijacking. Times out after 3s.
    private func readFromKeychain() -> String? {
        // Backoff after failures to avoid repeated prompts
        if let backoff = keychainBackoffUntil, Date() < backoff {
            return nil
        }

        let serviceName = "Claude Code-credentials"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", serviceName, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        // Prevent any UI interaction
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path]

        do {
            try process.run()

            // Timeout: 3 seconds
            let deadline = DispatchTime.now() + .seconds(3)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }
            if group.wait(timeout: deadline) == .timedOut {
                process.terminate()
                AppState.log("QuotaFetcher: Keychain read timed out")
                keychainBackoffUntil = Date().addingTimeInterval(60)
                return nil
            }

            guard process.terminationStatus == 0 else {
                // Not found or denied — backoff 60s
                keychainBackoffUntil = Date().addingTimeInterval(60)
                return nil
            }

            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !raw.isEmpty else { return nil }

            // The Keychain value is a JSON string containing credentials
            if let jsonData = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // Nested format: { claudeAiOauth: { accessToken: "..." } }
                if let oauth = json["claudeAiOauth"] as? [String: Any],
                   let token = oauth["accessToken"] as? String, !token.isEmpty {
                    AppState.log("QuotaFetcher: token from Keychain (nested)")
                    return token
                }
                // Flat format
                if let token = json["accessToken"] as? String, !token.isEmpty {
                    AppState.log("QuotaFetcher: token from Keychain (flat)")
                    return token
                }
            }

            // Raw token (not JSON)
            if raw.count > 20 && !raw.contains("{") {
                AppState.log("QuotaFetcher: token from Keychain (raw)")
                return raw
            }

            return nil
        } catch {
            AppState.log("QuotaFetcher: Keychain exec failed — \(error.localizedDescription)")
            keychainBackoffUntil = Date().addingTimeInterval(60)
            return nil
        }
    }

    // MARK: - Parse Response

    private func parse(_ data: Data) -> QuotaSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppState.log("QuotaFetcher: failed to parse JSON")
            return nil
        }

        let fh = parseTier(json["five_hour"])
        let sd = parseTier(json["seven_day"])
        let eu = parseExtraUsage(json["extra_usage"])
        let plan = QuotaSnapshot.detectPlan(extraUsage: eu)
        return QuotaSnapshot(
            fiveHour: fh,
            sevenDay: sd,
            sevenDayOpus: parseTier(json["seven_day_opus"]),
            sevenDaySonnet: parseTier(json["seven_day_sonnet"]),
            plan: plan,
            fetchedAt: Date(),
            extraUsage: eu
        )
    }

    private func parseTier(_ value: Any?) -> QuotaTier? {
        guard let dict = value as? [String: Any] else { return nil }
        // API returns "utilization" as percentage (0-100)
        let utilization = (dict["utilization"] as? Double)
            ?? (dict["utilization"] as? Int).map(Double.init)
            ?? 0
        let resetsAt: Date?
        if let str = dict["resets_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetsAt = formatter.date(from: str)
        } else {
            resetsAt = nil
        }
        return QuotaTier(utilization: utilization, resetsAt: resetsAt)
    }

    private func parseExtraUsage(_ value: Any?) -> ExtraUsageInfo? {
        guard let dict = value as? [String: Any] else { return nil }
        let isEnabled = dict["is_enabled"] as? Bool ?? false
        let monthlyLimit = dict["monthly_limit"] as? Double
        let usedCredits = dict["used_credits"] as? Double
        let utilization = dict["utilization"] as? Double
        return ExtraUsageInfo(isEnabled: isEnabled, monthlyLimit: monthlyLimit, usedCredits: usedCredits, utilization: utilization)
    }
}
