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

/// Minimal sender profile embedded alongside an invite when we render
/// it as a 1-line user card on the Invites tab.
struct InviteSenderSummary: Codable, Hashable {
    let id: UUID
    var bio: String?
    var gender: String?
    var genderVisible: Bool
    var tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case bio
        case gender
        case genderVisible = "gender_visible"
        case profileTags = "profile_tags"
    }

    init(id: UUID, bio: String?, gender: String?, genderVisible: Bool, tags: [String]) {
        self.id = id
        self.bio = bio
        self.gender = gender
        self.genderVisible = genderVisible
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.bio = try c.decodeIfPresent(String.self, forKey: .bio)
        self.gender = try c.decodeIfPresent(String.self, forKey: .gender)
        self.genderVisible = try c.decodeIfPresent(Bool.self, forKey: .genderVisible) ?? false
        struct TagRow: Decodable { let tag: String }
        let rows = try c.decodeIfPresent([TagRow].self, forKey: .profileTags) ?? []
        self.tags = rows.map(\.tag)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(bio, forKey: .bio)
        try c.encode(gender, forKey: .gender)
        try c.encode(genderVisible, forKey: .genderVisible)
        struct TagRow: Encodable { let tag: String }
        try c.encode(tags.map(TagRow.init), forKey: .profileTags)
    }

    /// Visible gender for badge rendering. Hidden if the sender opted out.
    var visibleGender: String? { genderVisible ? gender : nil }
}

/// Wraps an invite with the sender's profile fields needed for the
/// Invites-tab user card (gender badge + line + tags).
struct InviteWithSender: Identifiable, Hashable, Decodable {
    let invite: Invite
    let sender: InviteSenderSummary

    var id: UUID { invite.id }

    enum CodingKeys: String, CodingKey { case sender }

    init(from decoder: Decoder) throws {
        // The row is shaped like an Invite plus an embedded `sender` object.
        self.invite = try Invite(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sender = try c.decode(InviteSenderSummary.self, forKey: .sender)
    }

    init(invite: Invite, sender: InviteSenderSummary) {
        self.invite = invite
        self.sender = sender
    }
}
