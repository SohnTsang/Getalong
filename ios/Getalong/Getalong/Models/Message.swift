import Foundation

enum MessageType: String, Codable {
    case text
    case image
    case gif
    case video
    case system
}

struct Message: Codable, Identifiable, Hashable {
    let id: UUID
    var roomId: UUID
    var senderId: UUID
    var messageType: MessageType
    var body: String?
    var mediaId: UUID?
    var isDeleted: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roomId       = "room_id"
        case senderId     = "sender_id"
        case messageType  = "message_type"
        case body
        case mediaId      = "media_id"
        case isDeleted    = "is_deleted"
        case createdAt    = "created_at"
    }
}
