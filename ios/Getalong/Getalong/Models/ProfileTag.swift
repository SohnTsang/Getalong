import Foundation

struct ProfileTag: Codable, Identifiable, Hashable {
    let id: UUID
    var profileId: UUID
    var tag: String
    var normalizedTag: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case profileId     = "profile_id"
        case tag
        case normalizedTag = "normalized_tag"
        case createdAt     = "created_at"
    }
}

extension ProfileTag {
    /// Strip leading hash, collapse interior whitespace, lowercase.
    /// Returns nil for empty / over-length results.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.first == "#" { s.removeFirst() }
        s = s.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        let lowered = s.lowercased()
        guard !lowered.isEmpty, lowered.count <= 30 else { return nil }
        return lowered
    }

    /// User-facing form: trimmed and whitespace-collapsed but case preserved.
    static func display(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.first == "#" { s.removeFirst() }
        s = s.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        guard !s.isEmpty, s.count <= 30 else { return nil }
        return s
    }
}
