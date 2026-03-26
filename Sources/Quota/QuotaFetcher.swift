import Foundation
import Security

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

    /// Reads the OAuth access token. Caches after first read to avoid repeated Keychain prompts.
    private func resolveToken() -> String? {
        if let cached = cachedToken { return cached }
        // Try file first (no prompt)
        if let fileToken = readFromFile() {
            cachedToken = fileToken
            return fileToken
        }
        // Keychain fallback — will prompt ONCE, then cached for session lifetime
        if let keychainToken = readFromKeychain() {
            cachedToken = keychainToken
            AppState.log("QuotaFetcher: token cached from Keychain (no more prompts this session)")
            return keychainToken
        }
        return nil
    }

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == -128 {
                AppState.log("QuotaFetcher: Keychain access denied by user (click 'Always Allow' when prompted)")
            } else {
                AppState.log("QuotaFetcher: Keychain read failed (status \(status))")
            }
            return nil
        }

        // The Keychain entry is JSON: {"claudeAiOauth":{"accessToken":"sk-ant-oat...",...}}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let str, str.hasPrefix("sk-ant-") { return str }
            AppState.log("QuotaFetcher: Keychain data not parseable")
            return nil
        }

        // Try nested: claudeAiOauth.accessToken
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            return token
        }
        // Try flat: accessToken / access_token
        if let token = json["accessToken"] as? String ?? json["access_token"] as? String {
            return token
        }

        AppState.log("QuotaFetcher: no accessToken in Keychain JSON")
        return nil
    }

    private func readFromFile() -> String? {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/credentials.json")
        ]
        for path in paths {
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["accessToken"] as? String ?? json["access_token"] as? String else { continue }
            return token
        }
        return nil
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
