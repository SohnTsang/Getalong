import Foundation

enum MediaStatus: String, Codable {
    case active
    case viewed
    case expired
    case deleted
}

struct MediaAsset: Codable, Identifiable, Hashable {
    let id: UUID
    var ownerId: UUID
    var roomId: UUID
    var storagePath: String
    var mimeType: String
    var sizeBytes: Int64
    var durationSeconds: Int?
    var viewOnce: Bool
    var viewedBy: UUID?
    var viewedAt: Date?
    var status: MediaStatus
    var expiresAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId          = "owner_id"
        case roomId           = "room_id"
        case storagePath      = "storage_path"
        case mimeType         = "mime_type"
        case sizeBytes        = "size_bytes"
        case durationSeconds  = "duration_seconds"
        case viewOnce         = "view_once"
        case viewedBy         = "viewed_by"
        case viewedAt         = "viewed_at"
        case status
        case expiresAt        = "expires_at"
        case createdAt        = "created_at"
    }
}
