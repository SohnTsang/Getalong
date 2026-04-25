import Foundation

/// All invite mutations go through Edge Functions. The client never writes
/// to `invites`, `active_invite_locks`, or `missed_invite_accept_usage`
/// directly.
@MainActor
final class InviteService {
    static let shared = InviteService()
    private init() {}

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

    /// Edge Function: `sendLiveInvite`.
    func sendLiveInvite(receiverId: UUID,
                        postId: UUID? = nil,
                        message: String? = nil) async throws -> SendLiveInviteResponse {
        // TODO: invoke Edge Function.
        throw NSError(domain: "InviteService", code: -1)
    }

    /// Edge Function: `acceptLiveInvite`.
    func acceptLiveInvite(inviteId: UUID) async throws -> AcceptInviteResponse {
        // TODO
        throw NSError(domain: "InviteService", code: -1)
    }

    /// Edge Function: `declineInvite`.
    func declineInvite(inviteId: UUID) async throws {
        // TODO
    }

    /// Edge Function: `cancelLiveInvite`.
    func cancelLiveInvite(inviteId: UUID) async throws {
        // TODO
    }

    /// Edge Function: `acceptMissedInvite`.
    func acceptMissedInvite(inviteId: UUID) async throws -> AcceptInviteResponse {
        // TODO
        throw NSError(domain: "InviteService", code: -1)
    }

    /// Read-only listing.
    func fetchIncomingMissed() async throws -> [Invite] {
        // TODO
        return []
    }

    func fetchOutgoingActiveLive() async throws -> [Invite] {
        // TODO
        return []
    }
}
