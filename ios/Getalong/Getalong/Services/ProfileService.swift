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
    /// Taipei beta conversation-fit chips (mig 0034). All three are
    /// optional and may be cleared by sending an explicit JSON null
    /// via a dedicated clearing payload — Foundation's Encodable
    /// otherwise omits nil optionals.
    var connectionIntent: String?
    var lifestyleRhythm: String?
    var conversationDomain: String?

    enum CodingKeys: String, CodingKey {
        case displayName         = "display_name"
        case bio
        case gender
        case genderVisible       = "gender_visible"
        case city
        case country
        case languageCodes       = "language_codes"
        case interestedInGender  = "interested_in_gender"
        case connectionIntent    = "connection_intent"
        case lifestyleRhythm     = "lifestyle_rhythm"
        case conversationDomain  = "conversation_domain"
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
    /// Taipei beta fit chips. Onboarding picks these but allows skip,
    /// so all three are optional even at insert time.
    let connectionIntent: String?
    let lifestyleRhythm: String?
    let conversationDomain: String?

    enum CodingKeys: String, CodingKey {
        case id
        case getalongId          = "getalong_id"
        case displayName         = "display_name"
        case bio
        case birthYear           = "birth_year"
        case city
        case country
        case languageCodes       = "language_codes"
        case gender
        case genderVisible       = "gender_visible"
        case interestedInGender  = "interested_in_gender"
        case connectionIntent    = "connection_intent"
        case lifestyleRhythm     = "lifestyle_rhythm"
        case conversationDomain  = "conversation_domain"
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

    /// Update the Taipei beta conversation-fit chips. Encodes JSON
    /// nulls for cleared values (Foundation's default Encodable would
    /// otherwise omit them, leaving stale values server-side). Any
    /// combination of nil/value is allowed — the chips are optional.
    func updateMyConversationFit(
        intent: ConnectionIntent?,
        rhythm: LifestyleRhythm?,
        domain: ConversationDomain?
    ) async throws -> Profile {
        struct FitPayload: Encodable {
            let intent: String?
            let rhythm: String?
            let domain: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: Keys.self)
                // encodeIfPresent skips nil → field absent → server
                // keeps old value. We want the OPPOSITE: explicit null
                // when the user cleared the chip.
                if let v = intent { try c.encode(v, forKey: .intent) }
                else              { try c.encodeNil(forKey: .intent) }
                if let v = rhythm { try c.encode(v, forKey: .rhythm) }
                else              { try c.encodeNil(forKey: .rhythm) }
                if let v = domain { try c.encode(v, forKey: .domain) }
                else              { try c.encodeNil(forKey: .domain) }
            }
            enum Keys: String, CodingKey {
                case intent = "connection_intent"
                case rhythm = "lifestyle_rhythm"
                case domain = "conversation_domain"
            }
        }
        guard let userId = try? await Supa.client.auth.session.user.id else {
            throw ProfileError.underlying("not signed in")
        }
        let payload = FitPayload(intent: intent?.rawValue,
                                 rhythm: rhythm?.rawValue,
                                 domain: domain?.rawValue)
        do {
            let updated: Profile = try await Supa.client
                .from("profiles")
                .update(payload)
                .eq("id", value: userId)
                .select()
                .single()
                .execute()
                .value
            GALog.profile.info("updateMyConversationFit ok")
            return updated
        } catch {
            GALog.profile.error("updateMyConversationFit failed: \(error.localizedDescription)")
            throw Self.translate(error)
        }
    }

    /// Sets `city` and `country` back to NULL. Goes through a dedicated
    /// payload that emits explicit JSON `null` for both columns —
    /// `ProfilePatch` can't, because Foundation's default Encodable
    /// *omits* nil optionals (so a patch with city=nil, country=nil
    /// would be an empty UPDATE that doesn't actually clear anything).
    func clearMyRegion() async throws -> Profile {
        struct ClearRegion: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: Keys.self)
                try c.encodeNil(forKey: .city)
                try c.encodeNil(forKey: .country)
            }
            enum Keys: String, CodingKey { case city, country }
        }

        guard let userId = try? await Supa.client.auth.session.user.id else {
            GALog.profile.error("clearMyRegion: not signed in")
            throw ProfileError.underlying("not signed in")
        }
        GALog.profile.info("clearMyRegion begin user=\(userId)")
        do {
            let updated: Profile = try await Supa.client
                .from("profiles")
                .update(ClearRegion())
                .eq("id", value: userId)
                .select()
                .single()
                .execute()
                .value
            GALog.profile.info("clearMyRegion ok")
            return updated
        } catch {
            GALog.profile.error("clearMyRegion failed: \(error.localizedDescription)")
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
