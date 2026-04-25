import Foundation
import Supabase

enum InviteServiceError: LocalizedError, Equatable {
    case authRequired
    case profileNotFound
    case userBanned
    case receiverBanned
    case selfInviteNotAllowed
    case blockedRelationship
    case liveInviteSlotFull
    case duplicateLiveInvite
    case inviteNotFound
    case inviteNotActionable
    case liveInviteExpired
    case missedInviteExpired
    case missedAcceptLimitReached
    case activeChatLimitReached
    case chatAlreadyExists
    case receiverNotFound
    case invalidInput
    case other(String)

    init(code: String?, message: String?) {
        switch code {
        case "AUTH_REQUIRED":               self = .authRequired
        case "PROFILE_NOT_FOUND":           self = .profileNotFound
        case "USER_BANNED":                 self = .userBanned
        case "RECEIVER_BANNED":             self = .receiverBanned
        case "SELF_INVITE_NOT_ALLOWED":     self = .selfInviteNotAllowed
        case "BLOCKED_RELATIONSHIP":        self = .blockedRelationship
        case "LIVE_INVITE_SLOT_FULL":       self = .liveInviteSlotFull
        case "DUPLICATE_LIVE_INVITE":       self = .duplicateLiveInvite
        case "INVITE_NOT_FOUND":            self = .inviteNotFound
        case "INVITE_NOT_ACTIONABLE":       self = .inviteNotActionable
        case "LIVE_INVITE_EXPIRED":         self = .liveInviteExpired
        case "MISSED_INVITE_EXPIRED":       self = .missedInviteExpired
        case "MISSED_ACCEPT_LIMIT_REACHED": self = .missedAcceptLimitReached
        case "ACTIVE_CHAT_LIMIT_REACHED":   self = .activeChatLimitReached
        case "CHAT_ALREADY_EXISTS":         self = .chatAlreadyExists
        case "RECEIVER_NOT_FOUND":          self = .receiverNotFound
        case "INVALID_INPUT":               self = .invalidInput
        default:                            self = .other(message ?? "Something went wrong.")
        }
    }

    var errorDescription: String? {
        switch self {
        case .authRequired:               return "Please sign in again."
        case .profileNotFound:            return "Profile not found."
        case .userBanned:                 return "Your account is restricted."
        case .receiverBanned:             return "That person can't receive invites."
        case .selfInviteNotAllowed:       return "You can't invite yourself."
        case .blockedRelationship:        return "You can't invite this person."
        case .liveInviteSlotFull:         return "You already have a live invite out. Wait for it to finish or cancel it."
        case .duplicateLiveInvite:        return "You already sent them a live invite."
        case .inviteNotFound:             return "Invite not found."
        case .inviteNotActionable:        return "This invite can't be acted on right now."
        case .liveInviteExpired:          return "This live invite expired."
        case .missedInviteExpired:        return "This missed invite expired."
        case .missedAcceptLimitReached:   return "You've used your free missed-invite accepts for today."
        case .activeChatLimitReached:     return "You've reached your active chat limit."
        case .chatAlreadyExists:          return "A chat already exists with this person."
        case .receiverNotFound:           return "We couldn't find that handle."
        case .invalidInput:               return "Invalid request."
        case .other(let m):               return m
        }
    }
}

@MainActor
final class InviteService {
    static let shared = InviteService()
    private init() {}

    // MARK: - Edge Function payloads

    struct SendLiveInviteResponse: Decodable {
        let inviteId: UUID
        let liveExpiresAt: Date
        let durationSeconds: Int

        enum CodingKeys: String, CodingKey {
            case inviteId        = "invite_id"
            case liveExpiresAt   = "live_expires_at"
            case durationSeconds = "duration_seconds"
        }
    }

    struct AcceptInviteResponse: Decodable {
        let chatRoomId: UUID
        let inviteId: UUID

        enum CodingKeys: String, CodingKey {
            case chatRoomId = "chat_room_id"
            case inviteId   = "invite_id"
        }
    }

    private struct EnvelopeOK<T: Decodable>: Decodable { let ok: Bool; let data: T }
    private struct EnvelopeErr: Decodable {
        let ok: Bool
        let error_code: String?
        let message: String?
    }

    // MARK: - Mutations (via Edge Functions)

    func sendLiveInvite(receiverHandle: String, message: String?) async throws -> SendLiveInviteResponse {
        try await invoke(
            "sendLiveInvite",
            body: [
                "receiver_handle": .string(receiverHandle),
                "message":         .string(message ?? "")
            ].nilling("message", when: { ($0 as? String)?.isEmpty == true })
        )
    }

    func acceptLiveInvite(inviteId: UUID) async throws -> AcceptInviteResponse {
        try await invoke("acceptLiveInvite", body: ["invite_id": .string(inviteId.uuidString)])
    }

    func declineInvite(inviteId: UUID) async throws {
        let _: AcceptInviteIdResponse = try await invoke(
            "declineInvite", body: ["invite_id": .string(inviteId.uuidString)]
        )
    }

    func cancelLiveInvite(inviteId: UUID) async throws {
        let _: AcceptInviteIdResponse = try await invoke(
            "cancelLiveInvite", body: ["invite_id": .string(inviteId.uuidString)]
        )
    }

    func markLiveInviteMissed(inviteId: UUID) async throws {
        let _: AcceptInviteIdResponse = try await invoke(
            "markLiveInviteMissed", body: ["invite_id": .string(inviteId.uuidString)]
        )
    }

    func acceptMissedInvite(inviteId: UUID) async throws -> AcceptInviteResponse {
        try await invoke("acceptMissedInvite", body: ["invite_id": .string(inviteId.uuidString)])
    }

    private struct AcceptInviteIdResponse: Decodable { let inviteId: UUID
        enum CodingKeys: String, CodingKey { case inviteId = "invite_id" }
    }

    // MARK: - Reads (PostgREST, allowed by RLS for sender/receiver)

    func fetchIncomingLivePending(userId: UUID) async throws -> [Invite] {
        try await Supa.client
            .from("invites")
            .select()
            .eq("receiver_id", value: userId)
            .eq("status", value: "live_pending")
            .gt("live_expires_at", value: Date())
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchMissedInvites(userId: UUID) async throws -> [Invite] {
        try await Supa.client
            .from("invites")
            .select()
            .eq("receiver_id", value: userId)
            .eq("status", value: "missed")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchOutgoingLivePending(userId: UUID) async throws -> [Invite] {
        try await Supa.client
            .from("invites")
            .select()
            .eq("sender_id", value: userId)
            .eq("status", value: "live_pending")
            .gt("live_expires_at", value: Date())
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchInvite(id: UUID) async throws -> Invite? {
        let result: [Invite] = try await Supa.client
            .from("invites")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return result.first
    }

    // MARK: - Invocation

    private func invoke<T: Decodable>(_ name: String, body: [String: AnyJSON]) async throws -> T {
        do {
            let response: FunctionsResponse<Data> = try await Supa.client.functions
                .invoke(name, options: .init(body: body))
            let raw = response.data
            if let ok = try? JSONDecoder.gaInvite.decode(EnvelopeOK<T>.self, from: raw) {
                return ok.data
            }
            if let err = try? JSONDecoder.gaInvite.decode(EnvelopeErr.self, from: raw) {
                throw InviteServiceError(code: err.error_code, message: err.message)
            }
            throw InviteServiceError.other("Unexpected response.")
        } catch let e as InviteServiceError {
            throw e
        } catch let e as FunctionsError {
            // Edge Functions returned non-2xx; data still has our envelope.
            switch e {
            case .httpError(_, let data):
                if let err = try? JSONDecoder.gaInvite.decode(EnvelopeErr.self, from: data) {
                    throw InviteServiceError(code: err.error_code, message: err.message)
                }
                throw InviteServiceError.other(e.localizedDescription)
            default:
                throw InviteServiceError.other(e.localizedDescription)
            }
        } catch {
            throw InviteServiceError.other(error.localizedDescription)
        }
    }
}

// MARK: -

private extension JSONDecoder {
    static let gaInvite: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601WithFractional
        return d
    }()
}

private extension JSONDecoder.DateDecodingStrategy {
    /// Matches Postgres `timestamptz` ISO-8601 with fractional seconds.
    static var iso8601WithFractional: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ISO-8601 date: \(s)"
            ))
        }
    }
}

private extension Dictionary where Key == String, Value == AnyJSON {
    /// Drops a key whose underlying value matches a predicate.
    func nilling(_ key: String, when predicate: (Any) -> Bool) -> [String: AnyJSON] {
        var copy = self
        if case .string(let s)? = copy[key], predicate(s) {
            copy.removeValue(forKey: key)
        }
        return copy
    }
}
