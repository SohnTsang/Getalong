import Foundation
import Supabase

enum ProfileError: LocalizedError {
    case duplicateGetalongId
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .duplicateGetalongId: return "That handle is taken. Try another."
        case .underlying(let m):   return m
        }
    }
}

/// Payload sent to `public.profiles` on profile creation. Only the columns
/// the user actually controls during onboarding.
struct ProfileInsert: Encodable {
    let id: UUID
    let getalongId: String
    let displayName: String
    let bio: String?
    let birthYear: Int?
    let city: String?
    let country: String?
    let languageCodes: [String]
    let gender: String?
    let genderVisible: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case getalongId    = "getalong_id"
        case displayName   = "display_name"
        case bio
        case birthYear     = "birth_year"
        case city
        case country
        case languageCodes = "language_codes"
        case gender
        case genderVisible = "gender_visible"
    }
}

@MainActor
final class ProfileService {
    static let shared = ProfileService()
    private init() {}

    func fetchProfile(id: UUID) async throws -> Profile? {
        do {
            let result: [Profile] = try await Supa.client
                .from("profiles")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            return result.first
        } catch {
            throw ProfileError.underlying((error as NSError).localizedDescription)
        }
    }

    func fetchCurrentProfile() async throws -> Profile? {
        guard let userId = try? await Supa.client.auth.session.user.id else { return nil }
        return try await fetchProfile(id: userId)
    }

    func createProfile(_ payload: ProfileInsert) async throws -> Profile {
        do {
            let inserted: Profile = try await Supa.client
                .from("profiles")
                .insert(payload, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            return inserted
        } catch {
            throw Self.translate(error)
        }
    }

    func setTopics(profileId: UUID, topicIds: [UUID]) async throws {
        // Replace strategy: clear then insert. RLS allows both for own row.
        do {
            try await Supa.client
                .from("profile_topics")
                .delete()
                .eq("profile_id", value: profileId)
                .execute()

            guard !topicIds.isEmpty else { return }

            struct Row: Encodable {
                let profile_id: UUID
                let topic_id: UUID
            }
            let rows = topicIds.map { Row(profile_id: profileId, topic_id: $0) }
            try await Supa.client
                .from("profile_topics")
                .insert(rows)
                .execute()
        } catch {
            throw ProfileError.underlying((error as NSError).localizedDescription)
        }
    }

    func softDelete(userId: UUID) async throws {
        struct DeletePatch: Encodable { let deleted_at: Date }
        try await Supa.client
            .from("profiles")
            .update(DeletePatch(deleted_at: Date()))
            .eq("id", value: userId)
            .execute()
    }

    // MARK: -

    private static func translate(_ error: Error) -> ProfileError {
        let message = (error as NSError).localizedDescription
        let lower = message.lowercased()
        if lower.contains("duplicate") || lower.contains("23505")
            || lower.contains("unique") {
            return .duplicateGetalongId
        }
        return .underlying(message)
    }
}
