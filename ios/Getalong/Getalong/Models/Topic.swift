import Foundation

struct Topic: Codable, Identifiable, Hashable {
    let id: UUID
    var slug: String
    var nameEn: String
    var nameJa: String?
    var nameZh: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case nameEn    = "name_en"
        case nameJa    = "name_ja"
        case nameZh    = "name_zh"
        case createdAt = "created_at"
    }
}
