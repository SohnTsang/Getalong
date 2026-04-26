import Foundation
import Supabase

enum ProfileError: LocalizedError {
    case duplicateGetalongId
    case validation(String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .duplicateGetalongId: return String(localized: "error.duplicateHandle")
        case .validation(let m):   return m
        case .underlying:          return String(localized: "error.generic")
        }
    }
}

/// Whitelist of fields a user may update on their own profile from the
/// app. Sensitive fields (plan, is_banned, trust_score, deleted_at,
/// created_at, id, getalong_id) are also locked at the database level by
/// the profiles_lock_sensitive_columns trigger.
struct ProfilePatch: Encodable {
    var displayName: String?
    var bio: String?
    var gender: String?
    var genderVisible: Bool?
    var city: String?
    var country: String?
    var languageCodes: [String]?
    var interestedInGender: String?

    enum CodingKeys: String, CodingKey {
        case displayName        = "display_name"
        case bio
        case gender
        case genderVisible      = "gender_visible"
        case city
        case country
        case languageCodes      = "language_codes"
        case interestedInGender = "interested_in_gender"
    }
}

/// Server-aligned bounds for client-side validation. The DB-side bio
/// constraint allows up to 500 (matches the posts table); we cap UI at
/// 160 for the one-line signal.
enum ProfileLimits {
    static let displayNameMax = 40
    static let signalMax      = 160
    static let cityMax        = 80
    static let countryMax     = 80
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
    let interestedInGender: String?

    enum CodingKeys: String, CodingKey {
        case id
        case getalongId         = "getalong_id"
        case displayName        = "display_name"
        case bio
        case birthYear          = "birth_year"
        case city
        case country
        case languageCodes      = "language_codes"
        case gender
        case genderVisible      = "gender_visible"
        case interestedInGender = "interested_in_gender"
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
        GALog.profile.info("createProfile handle=@\(payload.getalongId)")
        do {
            let inserted: Profile = try await Supa.client
                .from("profiles")
                .insert(payload, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            GALog.profile.info("createProfile ok id=\(inserted.id)")
            return inserted
        } catch {
            GALog.profile.error("createProfile failed: \(error.localizedDescription)")
            throw Self.translate(error)
        }
    }

    /// Updates the caller's profile. Only fields whitelisted by
    /// `ProfilePatch` may be changed; sensitive columns are also locked
    /// at the DB level. Returns the freshly-fetched row.
    func updateMyProfile(_ patch: ProfilePatch) async throws -> Profile {
        guard let userId = try? await Supa.client.auth.session.user.id else {
            GALog.profile.error("updateMyProfile: not signed in")
            throw ProfileError.underlying("not signed in")
        }
        GALog.profile.info("updateMyProfile begin user=\(userId)")
        do {
            let updated: Profile = try await Supa.client
                .from("profiles")
                .update(patch)
                .eq("id", value: userId)
                .select()
                .single()
                .execute()
                .value
            GALog.profile.info("updateMyProfile ok")
            return updated
        } catch {
            GALog.profile.error("updateMyProfile failed: \(error.localizedDescription)")
            throw Self.translate(error)
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
