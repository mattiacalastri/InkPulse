import Foundation

enum JSONLParser {

    // MARK: - Public

    /// Parse a single JSONL line into a typed ClaudeEvent.
    static func parse(line: String) -> ClaudeEvent {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        guard let type = root["type"] as? String,
              let timestamp = parseTimestamp(root["timestamp"]),
              let sessionId = root["session_id"] as? String else {
            return .unknown
        }

        switch type {
        case "assistant":
            return parseAssistant(root, timestamp: timestamp, sessionId: sessionId)
        case "progress":
            return parseProgress(root, timestamp: timestamp, sessionId: sessionId)
        case "user":
            return .user(timestamp: timestamp, sessionId: sessionId)
        case "system":
            return .system(timestamp: timestamp, sessionId: sessionId)
        case "queue-operation":
            let operation = root["operation"] as? String ?? "unknown"
            return .queueOperation(operation: operation, timestamp: timestamp, sessionId: sessionId)
        default:
            return .unknown
        }
    }

    // MARK: - Private helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        return isoFormatter.date(from: str)
    }

    /// Decode the `message` field which may be a JSON object, a JSON string, or a
    /// Python-repr string (single quotes).
    private static func decodeMessage(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        guard var str = value as? String else { return nil }
        // Try as-is first (valid JSON string)
        if let data = str.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        // Python repr: replace single quotes with double quotes (simple heuristic)
        str = str.replacingOccurrences(of: "'", with: "\"")
        if let data = str.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return nil
    }

    // MARK: - Assistant

    private static func parseAssistant(_ root: [String: Any], timestamp: Date, sessionId: String) -> ClaudeEvent {
        let message = decodeMessage(root["message"]) ?? [:]

        let model = message["model"] as? String ?? "unknown"
        let requestId = (message["request_id"] ?? root["request_id"]) as? String

        // Usage
        let usageDict = message["usage"] as? [String: Any] ?? [:]
        let usage = TokenUsage(
            inputTokens: usageDict["input_tokens"] as? Int ?? 0,
            outputTokens: usageDict["output_tokens"] as? Int ?? 0,
            cacheReadInputTokens: usageDict["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: usageDict["cache_creation_input_tokens"] as? Int ?? 0
        )

        // Content blocks
        var thinkingText: String?
        var outputText: String?

        if let contentBlocks = message["content"] as? [[String: Any]] {
            for block in contentBlocks {
                let blockType = block["type"] as? String
                if blockType == "thinking", let text = block["thinking"] as? String {
                    thinkingText = text
                } else if blockType == "text", let text = block["text"] as? String {
                    outputText = text
                }
            }
        }

        let msg = AssistantMessage(
            model: model,
            usage: usage,
            thinkingText: thinkingText,
            outputText: outputText,
            requestId: requestId
        )
        return .assistant(msg, timestamp: timestamp, sessionId: sessionId)
    }

    // MARK: - Progress

    private static func parseProgress(_ root: [String: Any], timestamp: Date, sessionId: String) -> ClaudeEvent {
        let toolUseID = root["tool_use_id"] as? String
        let dataStr = root["data"] as? String ?? ""

        let isHookProgress = dataStr.contains("hook_progress")
        let isToolUse = !isHookProgress && toolUseID != nil

        let lowered = dataStr.lowercased()
        let isError = lowered.contains("error")
            || lowered.contains("denied")
            || lowered.contains("blocked")
            || lowered.contains("failed")

        return .progress(
            toolUseID: toolUseID,
            isToolUse: isToolUse,
            isError: isError,
            timestamp: timestamp,
            sessionId: sessionId
        )
    }
}
