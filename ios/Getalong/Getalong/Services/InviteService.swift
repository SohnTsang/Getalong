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
        case .authRequired:               return String(localized: "error.notSignedIn")
        case .profileNotFound:            return String(localized: "error.profileNotFound")
        case .userBanned:                 return String(localized: "error.userBanned")
        case .receiverBanned:             return String(localized: "error.receiverBanned")
        case .selfInviteNotAllowed:       return String(localized: "error.selfInviteNotAllowed")
        case .blockedRelationship:        return String(localized: "error.blockedRelationship")
        case .liveInviteSlotFull:         return String(localized: "error.liveSignalSlotFull")
        case .duplicateLiveInvite:        return String(localized: "error.duplicateLiveSignal")
        case .inviteNotFound:             return String(localized: "error.inviteNotFound")
        case .inviteNotActionable:        return String(localized: "error.inviteNotActionable")
        case .liveInviteExpired:          return String(localized: "error.liveInviteExpired")
        case .missedInviteExpired:        return String(localized: "error.missedInviteExpired")
        case .missedAcceptLimitReached:   return String(localized: "error.missedAcceptLimitReached")
        case .activeChatLimitReached:     return String(localized: "error.activeChatLimitReached")
        case .chatAlreadyExists:          return String(localized: "error.chatAlreadyExists")
        case .receiverNotFound:           return String(localized: "error.receiverNotFound")
        case .invalidInput:               return String(localized: "error.invalidInput")
        case .other:                      return String(localized: "error.generic")
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

    func sendLiveInvite(receiverHandle: String) async throws -> SendLiveInviteResponse {
        try await invoke(
            "sendLiveInvite",
            body: ["receiver_handle": .string(receiverHandle)]
        )
    }

    /// Tap-to-invite from a profile id (used from Discovery once it ships).
    func sendLiveInvite(receiverId: UUID) async throws -> SendLiveInviteResponse {
        try await invoke(
            "sendLiveInvite",
            body: ["receiver_id": .string(receiverId.uuidString)]
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
            let raw = try await Supa.invokeRaw(name, body: body)
            if let ok = try? JSONDecoder.gaInvite.decode(EnvelopeOK<T>.self, from: raw) {
                return ok.data
            }
            if let err = try? JSONDecoder.gaInvite.decode(EnvelopeErr.self, from: raw) {
                throw InviteServiceError(code: err.error_code, message: err.message)
            }
            throw InviteServiceError.other("Unexpected response.")
        } catch let e as InviteServiceError {
            throw e
        } catch {
            // Edge Functions return non-2xx with our envelope embedded;
            // supabase-swift surfaces it as FunctionsError.httpError(code, data).
            if let data = Self.errorPayload(from: error),
               let err  = try? JSONDecoder.gaInvite.decode(EnvelopeErr.self, from: data) {
                throw InviteServiceError(code: err.error_code, message: err.message)
            }
            throw InviteServiceError.other(error.localizedDescription)
        }
    }

    /// Best-effort extraction of the JSON body from `FunctionsError.httpError`
    /// without taking a hard compile-time dependency on the enum shape (it
    /// has shifted between supabase-swift releases).
    private static func errorPayload(from error: Error) -> Data? {
        let mirror = Mirror(reflecting: error)
        for child in mirror.children {
            if let nested = Mirror(reflecting: child.value).children.first(where: { _ in true })?.value,
               let data = nested as? Data {
                return data
            }
            if let data = child.value as? Data { return data }
        }
        return nil
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

