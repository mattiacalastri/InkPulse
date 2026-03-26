import Foundation

// MARK: - Inbound (Session → InkPulse)

enum WSInbound: Codable {
    case status(WSStatusMessage)
    case heartbeat(sessionId: String)

    enum CodingKeys: String, CodingKey { case type, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "status":
            self = .status(try container.decode(WSStatusMessage.self, forKey: .data))
        case "heartbeat":
            let data = try container.decode([String: String].self, forKey: .data)
            self = .heartbeat(sessionId: data["session_id"] ?? "")
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .status(let msg):
            try container.encode("status", forKey: .type)
            try container.encode(msg, forKey: .data)
        case .heartbeat(let sid):
            try container.encode("heartbeat", forKey: .type)
            try container.encode(["session_id": sid], forKey: .data)
        }
    }
}

struct WSStatusMessage: Codable {
    let sessionId: String
    let cwd: String
    let state: String
    let currentTool: String?
    let currentTarget: String?
    let task: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd, state
        case currentTool = "current_tool"
        case currentTarget = "current_target"
        case task
    }
}

// MARK: - Outbound (InkPulse → Session)

enum WSOutbound: Codable {
    case command(WSCommandMessage)
    case notify(WSNotifyMessage)

    enum CodingKeys: String, CodingKey { case type, data }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .command(let msg):
            try container.encode("command", forKey: .type)
            try container.encode(msg, forKey: .data)
        case .notify(let msg):
            try container.encode("notify", forKey: .type)
            try container.encode(msg, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "command": self = .command(try container.decode(WSCommandMessage.self, forKey: .data))
        case "notify": self = .notify(try container.decode(WSNotifyMessage.self, forKey: .data))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown: \(type)")
        }
    }
}

struct WSCommandMessage: Codable {
    let action: String
    let prompt: String?
}

struct WSNotifyMessage: Codable {
    let fromTeam: String
    let fromRole: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case fromTeam = "from_team"
        case fromRole = "from_role"
        case message
    }
}
