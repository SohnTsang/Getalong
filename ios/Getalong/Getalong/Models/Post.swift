import Foundation

struct Post: Codable, Identifiable, Hashable {
    let id: UUID
    var authorId: UUID
    var content: String
    var mood: String?
    var visibility: String
    var city: String?
    var country: String?
    var isHidden: Bool
    var deletedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorId   = "author_id"
        case content
        case mood
        case visibility
        case city
        case country
        case isHidden   = "is_hidden"
        case deletedAt  = "deleted_at"
        case createdAt  = "created_at"
    }
}
