import Foundation

enum JSONLParser {

    /// Maps toolUseID → toolName, populated from assistant events, consumed by progress events.
    private static var toolNameRegistry: [String: String] = [:]

    // MARK: - Public

    /// Parse a single JSONL line into a typed ClaudeEvent.
    static func parse(line: String) -> ClaudeEvent {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        guard let type = root["type"] as? String,
              let timestamp = parseTimestamp(root["timestamp"]),
              let sessionId = root["sessionId"] as? String else {
            return .unknown
        }

        switch type {
        case "assistant":
            return parseAssistant(root, timestamp: timestamp, sessionId: sessionId)
        case "progress":
            return parseProgress(root, timestamp: timestamp, sessionId: sessionId)
        case "user":
            return parseUser(root, timestamp: timestamp, sessionId: sessionId)
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
        var toolUses: [ToolUseInfo] = []

        if let contentBlocks = message["content"] as? [[String: Any]] {
            for block in contentBlocks {
                let blockType = block["type"] as? String
                if blockType == "thinking", let text = block["thinking"] as? String {
                    thinkingText = text
                } else if blockType == "text", let text = block["text"] as? String {
                    outputText = text
                } else if blockType == "tool_use",
                          let toolId = block["id"] as? String,
                          let toolName = block["name"] as? String {
                    let target = extractToolTarget(from: block["input"] as? [String: Any], toolName: toolName)
                    toolUses.append(ToolUseInfo(id: toolId, name: toolName, target: target))
                    toolNameRegistry[toolId] = toolName
                }
            }
        }

        let msg = AssistantMessage(
            model: model,
            usage: usage,
            thinkingText: thinkingText,
            outputText: outputText,
            requestId: requestId,
            toolUses: toolUses
        )
        return .assistant(msg, timestamp: timestamp, sessionId: sessionId)
    }

    // MARK: - Tool Target Extraction

    /// Extracts the first meaningful argument from tool_use input. Truncated to 30 chars.
    private static func extractToolTarget(from input: [String: Any]?, toolName: String) -> String? {
        guard let input = input else { return nil }

        // Priority: file_path → command → pattern → first string value
        let keys = ["file_path", "command", "pattern", "query", "url"]
        for key in keys {
            if let value = input[key] as? String, !value.isEmpty {
                return truncateTarget(value)
            }
        }

        // Fallback: first string value that is not too long
        for (_, value) in input {
            if let str = value as? String, !str.isEmpty, str.count < 200 {
                return truncateTarget(str)
            }
        }

        return nil
    }

    private static func truncateTarget(_ value: String) -> String {
        // For file paths, take just the last component
        if value.contains("/") {
            let last = URL(fileURLWithPath: value).lastPathComponent
            if last.count <= 30 { return last }
            return String(last.prefix(30))
        }
        if value.count <= 30 { return value }
        return String(value.prefix(30))
    }

    // MARK: - User (tool_result errors)

    private static func parseUser(_ root: [String: Any], timestamp: Date, sessionId: String) -> ClaudeEvent {
        var errorCount = 0

        // user events contain tool_result blocks with is_error flag
        let message = decodeMessage(root["message"]) ?? [:]
        if let contentBlocks = message["content"] as? [[String: Any]] {
            for block in contentBlocks {
                if block["type"] as? String == "tool_result",
                   let isError = block["is_error"] as? Bool,
                   isError {
                    errorCount += 1
                }
            }
        }

        // Also check for error keywords in data field (progress-style user events)
        if let data = root["data"] as? String {
            let dataMsg = decodeMessage(data)
            if let innerMsg = dataMsg?["message"] as? [String: Any],
               let content = innerMsg["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_result",
                       let isError = block["is_error"] as? Bool,
                       isError {
                        errorCount += 1
                    }
                }
            }
        }

        return .user(errorCount: errorCount, timestamp: timestamp, sessionId: sessionId)
    }

    // MARK: - Progress

    private static func parseProgress(_ root: [String: Any], timestamp: Date, sessionId: String) -> ClaudeEvent {
        let toolUseID = (root["toolUseID"] ?? root["tool_use_id"]) as? String
        let dataStr = root["data"] as? String ?? ""

        let isHookProgress = dataStr.contains("hook_progress")
        let isToolUse = !isHookProgress && toolUseID != nil

        let lowered = dataStr.lowercased()
        let isError = lowered.contains("error")
            || lowered.contains("denied")
            || lowered.contains("blocked")
            || lowered.contains("failed")

        // Resolve tool name from registry
        let toolName: String?
        if let id = toolUseID {
            toolName = toolNameRegistry[id]
        } else {
            toolName = nil
        }

        return .progress(
            toolUseID: toolUseID,
            toolName: toolName,
            isToolUse: isToolUse,
            isError: isError,
            timestamp: timestamp,
            sessionId: sessionId
        )
    }
}
