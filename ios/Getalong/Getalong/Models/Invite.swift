import Foundation

enum InviteStatus: String, Codable {
    case livePending     = "live_pending"
    case liveAccepted    = "live_accepted"
    case missed          = "missed"
    case missedAccepted  = "missed_accepted"
    case declined        = "declined"
    case cancelled       = "cancelled"
    case expired         = "expired"
}

enum InviteDeliveryMode: String, Codable {
    case live
    case missed
}

enum InviteType: String, Codable {
    case normal
    case `super`
}

struct Invite: Codable, Identifiable, Hashable {
    let id: UUID
    var senderId: UUID
    var receiverId: UUID
    var postId: UUID?
    var message: String?
    var inviteType: InviteType
    var deliveryMode: InviteDeliveryMode
    var status: InviteStatus
    var liveExpiresAt: Date
    var missedExpiresAt: Date?
    var acceptedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderId         = "sender_id"
        case receiverId       = "receiver_id"
        case postId           = "post_id"
        case message
        case inviteType       = "invite_type"
        case deliveryMode     = "delivery_mode"
        case status
        case liveExpiresAt    = "live_expires_at"
        case missedExpiresAt  = "missed_expires_at"
        case acceptedAt       = "accepted_at"
        case createdAt        = "created_at"
    }

    /// Seconds remaining for a live-pending invite. Negative if expired.
    var liveSecondsRemaining: TimeInterval {
        liveExpiresAt.timeIntervalSinceNow
    }
}
