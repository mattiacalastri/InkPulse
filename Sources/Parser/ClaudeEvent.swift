import Foundation

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
}

struct ToolUseInfo {
    let id: String
    let name: String
    let target: String?  // first argument (file_path, command, pattern), truncated to 30 chars
}

struct AssistantMessage {
    let model: String
    let usage: TokenUsage
    let thinkingText: String?
    let outputText: String?
    let requestId: String?
    let toolUses: [ToolUseInfo]
}

enum ClaudeEvent {
    case assistant(AssistantMessage, timestamp: Date, sessionId: String)
    case progress(toolUseID: String?, toolName: String?, isToolUse: Bool, isError: Bool, timestamp: Date, sessionId: String)
    case user(errorCount: Int, timestamp: Date, sessionId: String)
    case system(timestamp: Date, sessionId: String)
    case queueOperation(operation: String, timestamp: Date, sessionId: String)
    case unknown

    var timestamp: Date? {
        switch self {
        case .assistant(_, let ts, _), .progress(_, _, _, _, let ts, _),
             .user(_, let ts, _), .system(let ts, _),
             .queueOperation(_, let ts, _):
            return ts
        case .unknown: return nil
        }
    }

    var sessionId: String? {
        switch self {
        case .assistant(_, _, let sid), .progress(_, _, _, _, _, let sid),
             .user(_, _, let sid), .system(_, let sid),
             .queueOperation(_, _, let sid):
            return sid
        case .unknown: return nil
        }
    }
}
