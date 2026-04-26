import Foundation
import Supabase

enum ProfileTagError: LocalizedError, Equatable {
    case empty
    case tooLong
    case duplicate
    case limitReached
    case underlying

    var errorDescription: String? {
        switch self {
        case .empty:        return String(localized: "profile.tags.tooLong")
        case .tooLong:      return String(localized: "profile.tags.tooLong")
        case .duplicate:    return String(localized: "profile.tags.duplicate")
        case .limitReached: return String(localized: "profile.tags.limitReached")
        case .underlying:   return String(localized: "error.generic")
        }
    }
}

@MainActor
final class ProfileTagService {
    static let shared = ProfileTagService()
    private init() {}

    static let maxTagsPerProfile = 10
    static let maxTagLength = 30

    // MARK: - Tag suggestions (featured + recent)

    struct TagSuggestion: Decodable, Hashable {
        let tag: String
        let count: Int?
        let normalizedTag: String?
        enum CodingKeys: String, CodingKey {
            case tag
            case count
            case normalizedTag = "normalized_tag"
        }
    }

    struct TagSuggestions: Decodable {
        let featured: [TagSuggestion]
        let recent: [TagSuggestion]
    }

    /// Calls the getTagSuggestions Edge Function. Returns featured (top
    /// 20 across the platform) and recent (caller's last 20). Failures
    /// surface as empty lists so the editor still works.
    func fetchSuggestions() async -> TagSuggestions {
        struct Body: Encodable {}
        do {
            let raw = try await Supa.invokeRaw("getTagSuggestions", body: Body())
            struct Envelope: Decodable { let ok: Bool; let data: TagSuggestions }
            let env = try JSONDecoder().decode(Envelope.self, from: raw)
            return env.data
        } catch {
            GALog.profile.error("getTagSuggestions: \(error.localizedDescription)")
            return TagSuggestions(featured: [], recent: [])
        }
    }

    /// Read tags for a given profile.
    func fetchTags(for profileId: UUID) async throws -> [ProfileTag] {
        try await Supa.client
            .from("profile_tags")
            .select()
            .eq("profile_id", value: profileId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func fetchMyTags() async throws -> [ProfileTag] {
        guard let uid = try? await Supa.client.auth.session.user.id else { return [] }
        return try await fetchTags(for: uid)
    }

    /// Insert one tag for the current user. Validates locally first.
    func addTag(_ raw: String, existing: [ProfileTag]) async throws -> ProfileTag {
        guard let display = ProfileTag.display(raw),
              let normalized = ProfileTag.normalize(raw) else {
            throw ProfileTagError.empty
        }
        guard display.count <= Self.maxTagLength,
              normalized.count <= Self.maxTagLength else {
            throw ProfileTagError.tooLong
        }
        guard !existing.contains(where: { $0.normalizedTag == normalized }) else {
            throw ProfileTagError.duplicate
        }
        guard existing.count < Self.maxTagsPerProfile else {
            throw ProfileTagError.limitReached
        }

        guard let uid = try? await Supa.client.auth.session.user.id else {
            throw ProfileTagError.underlying
        }

        struct Insert: Encodable {
            let profile_id: UUID
            let tag: String
            let normalized_tag: String
        }
        do {
            let inserted: ProfileTag = try await Supa.client
                .from("profile_tags")
                .insert(Insert(profile_id: uid,
                               tag: display,
                               normalized_tag: normalized),
                        returning: .representation)
                .select()
                .single()
                .execute()
                .value
            return inserted
        } catch {
            let lower = (error as NSError).localizedDescription.lowercased()
            if lower.contains("tag_limit_reached") { throw ProfileTagError.limitReached }
            if lower.contains("duplicate") || lower.contains("unique") {
                throw ProfileTagError.duplicate
            }
            GALog.app.error("addTag failed: \(error.localizedDescription)")
            throw ProfileTagError.underlying
        }
    }

    func deleteTag(id: UUID) async throws {
        do {
            try await Supa.client
                .from("profile_tags")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch {
            GALog.app.error("deleteTag failed: \(error.localizedDescription)")
            throw ProfileTagError.underlying
        }
    }
}
