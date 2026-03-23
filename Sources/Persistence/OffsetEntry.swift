import Foundation

struct OffsetEntry: Codable {
    let file: String
    let offset: UInt64
    let lastTs: String?

    enum CodingKeys: String, CodingKey {
        case file, offset
        case lastTs = "last_ts"
    }
}
