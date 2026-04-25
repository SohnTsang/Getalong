import Foundation

enum ChatRoomStatus: String, Codable {
    case active
    case archived
    case blocked
}

struct ChatRoom: Codable, Identifiable, Hashable {
    let id: UUID
    var inviteId: UUID?
    var userA: UUID
    var userB: UUID
    var status: ChatRoomStatus
    var createdAt: Date
    var lastMessageAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case inviteId       = "invite_id"
        case userA          = "user_a"
        case userB          = "user_b"
        case status
        case createdAt      = "created_at"
        case lastMessageAt  = "last_message_at"
    }

    func partnerId(currentUser: UUID) -> UUID {
        userA == currentUser ? userB : userA
    }
}
