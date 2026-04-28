import Foundation

enum MediaStatus: String, Codable {
    case pendingUpload = "pending_upload"
    case active
    case viewed
    case expired
    case deleted
    case quarantined
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
    var uploadedAt: Date?
    var attachedMessageId: UUID?
    var storageDeletedAt: Date?
    var createdAt: Date
    /// Base64-encoded tiny JPEG (~24px). Both participants render it
    /// as a heavily blurred backdrop with our dotted-noise overlay so
    /// the bubble shows the *same* placeholder content on either side
    /// — view-once enforcement is unchanged because the original
    /// bytes still only leave storage on tap.
    var previewData: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId            = "owner_id"
        case roomId             = "room_id"
        case storagePath        = "storage_path"
        case mimeType           = "mime_type"
        case sizeBytes          = "size_bytes"
        case durationSeconds    = "duration_seconds"
        case viewOnce           = "view_once"
        case viewedBy           = "viewed_by"
        case viewedAt           = "viewed_at"
        case status
        case expiresAt          = "expires_at"
        case uploadedAt         = "uploaded_at"
        case attachedMessageId  = "attached_message_id"
        case storageDeletedAt   = "storage_deleted_at"
        case createdAt          = "created_at"
        case previewData        = "preview_data"
    }
}
