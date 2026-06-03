import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var getalongId: String
    var displayName: String
    var bio: String?
    var gender: String?
    var genderVisible: Bool
    var interestedInGender: String?
    var birthYear: Int?
    var city: String?
    var country: String?
    var languageCodes: [String]
    /// Taipei beta "conversation fit" chips. All optional — legacy
    /// users have nulls until they pick. Discovery treats these as
    /// soft context only (sort hint, never a hard filter).
    var connectionIntent: String?
    var lifestyleRhythm: String?
    var conversationDomain: String?
    var trustScore: Int
    var plan: SubscriptionPlan
    var isBanned: Bool
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    /// Convenience: typed accessors. Unknown raw values resolve to nil
    /// rather than crashing — protects against drift between migration
    /// CHECK and Swift enum.
    var connectionIntentTyped: ConnectionIntent? {
        connectionIntent.flatMap { ConnectionIntent(rawValue: $0) }
    }
    var lifestyleRhythmTyped: LifestyleRhythm? {
        lifestyleRhythm.flatMap { LifestyleRhythm(rawValue: $0) }
    }
    var conversationDomainTyped: ConversationDomain? {
        conversationDomain.flatMap { ConversationDomain(rawValue: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case getalongId    = "getalong_id"
        case displayName   = "display_name"
        case bio
        case gender
        case genderVisible      = "gender_visible"
        case interestedInGender = "interested_in_gender"
        case birthYear          = "birth_year"
        case city
        case country
        case languageCodes      = "language_codes"
        case connectionIntent   = "connection_intent"
        case lifestyleRhythm    = "lifestyle_rhythm"
        case conversationDomain = "conversation_domain"
        case trustScore         = "trust_score"
        case plan
        case isBanned      = "is_banned"
        case deletedAt     = "deleted_at"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }
}
