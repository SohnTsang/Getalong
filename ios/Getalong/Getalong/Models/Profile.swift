import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var getalongId: String
    var displayName: String
    var bio: String?
    var gender: String?
    var genderVisible: Bool
    var birthYear: Int?
    var city: String?
    var country: String?
    var languageCodes: [String]
    var trustScore: Int
    var plan: SubscriptionPlan
    var isBanned: Bool
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case getalongId    = "getalong_id"
        case displayName   = "display_name"
        case bio
        case gender
        case genderVisible = "gender_visible"
        case birthYear     = "birth_year"
        case city
        case country
        case languageCodes = "language_codes"
        case trustScore    = "trust_score"
        case plan
        case isBanned      = "is_banned"
        case deletedAt     = "deleted_at"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }
}
