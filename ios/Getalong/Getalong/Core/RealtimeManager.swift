import Foundation

/// Subscribes to Supabase Realtime channels for invites and chat messages.
/// Placeholder until `supabase-swift` is wired in.
final class RealtimeManager {
    static let shared = RealtimeManager()
    private init() {}

    func subscribeToInvites(receiverId: UUID,
                            onChange: @escaping (Invite) -> Void) {
        // TODO: subscribe to `invites` filtered by receiver_id.
    }

    func subscribeToMessages(roomId: UUID,
                             onMessage: @escaping (Message) -> Void) {
        // TODO: subscribe to `messages` filtered by room_id.
    }

    func unsubscribeAll() {
        // TODO
    }
}
