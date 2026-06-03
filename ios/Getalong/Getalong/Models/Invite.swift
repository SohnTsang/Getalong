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
    /// Taipei beta conversation-fit chips. All three are optional —
    /// legacy profiles (and any payload that predates the RPC update
    /// in migration 0035 / the embed update in InviteService) decode
    /// these as nil and the Invite card simply hides the chip.
    var connectionIntent:   String?
    var lifestyleRhythm:    String?
    var conversationDomain: String?

    enum CodingKeys: String, CodingKey {
        case id
        case bio
        case gender
        case genderVisible       = "gender_visible"
        case connectionIntent    = "connection_intent"
        case lifestyleRhythm     = "lifestyle_rhythm"
        case conversationDomain  = "conversation_domain"
        case profileTags         = "profile_tags"
    }

    init(id: UUID,
         bio: String?,
         gender: String?,
         genderVisible: Bool,
         tags: [String],
         connectionIntent: String? = nil,
         lifestyleRhythm: String? = nil,
         conversationDomain: String? = nil) {
        self.id = id
        self.bio = bio
        self.gender = gender
        self.genderVisible = genderVisible
        self.tags = tags
        self.connectionIntent = connectionIntent
        self.lifestyleRhythm = lifestyleRhythm
        self.conversationDomain = conversationDomain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.bio = try c.decodeIfPresent(String.self, forKey: .bio)
        self.gender = try c.decodeIfPresent(String.self, forKey: .gender)
        self.genderVisible = try c.decodeIfPresent(Bool.self, forKey: .genderVisible) ?? false
        self.connectionIntent   = try c.decodeIfPresent(String.self, forKey: .connectionIntent)
        self.lifestyleRhythm    = try c.decodeIfPresent(String.self, forKey: .lifestyleRhythm)
        self.conversationDomain = try c.decodeIfPresent(String.self, forKey: .conversationDomain)
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
        try c.encodeIfPresent(connectionIntent,   forKey: .connectionIntent)
        try c.encodeIfPresent(lifestyleRhythm,    forKey: .lifestyleRhythm)
        try c.encodeIfPresent(conversationDomain, forKey: .conversationDomain)
        struct TagRow: Encodable { let tag: String }
        try c.encode(tags.map(TagRow.init), forKey: .profileTags)
    }

    /// Visible gender for badge rendering. Hidden if the sender opted out.
    var visibleGender: String? { genderVisible ? gender : nil }

    /// Convenience typed accessors. Mirror the pattern on
    /// `Profile.connectionIntentTyped` etc. — unknown raw values
    /// resolve to nil rather than crashing if backend enums drift
    /// ahead of the Swift enum.
    var connectionIntentTyped:   ConnectionIntent? {
        connectionIntent.flatMap { ConnectionIntent(rawValue: $0) }
    }
    var lifestyleRhythmTyped:    LifestyleRhythm? {
        lifestyleRhythm.flatMap { LifestyleRhythm(rawValue: $0) }
    }
    var conversationDomainTyped: ConversationDomain? {
        conversationDomain.flatMap { ConversationDomain(rawValue: $0) }
    }
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
