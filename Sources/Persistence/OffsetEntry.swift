import Foundation

struct OffsetEntry: Codable {
    let file: String
    let offset: UInt64
    let lastTs: String?
    let mtime: Date?
    let fileSize: UInt64?

    enum CodingKeys: String, CodingKey {
        case file, offset, mtime
        case lastTs = "last_ts"
        case fileSize = "file_size"
    }
}
