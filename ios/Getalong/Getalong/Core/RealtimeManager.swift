import Foundation
import Supabase

/// Subscribes to Supabase Realtime postgres-changes for the current user's
/// incoming invites. Fires a closure on any change so callers can refetch.
@MainActor
final class RealtimeInviteManager {
    static let shared = RealtimeInviteManager()
    private init() {}

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?

    /// Begin listening. Replaces any prior subscription.
    func start(userId: UUID, onInviteChange: @escaping () -> Void) async {
        await stop()

        let ch = await Supa.client.realtimeV2.channel("invites:receiver=\(userId.uuidString)")
        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "invites",
            filter: "receiver_id=eq.\(userId.uuidString)"
        )
        let updates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "invites",
            filter: "receiver_id=eq.\(userId.uuidString)"
        )
        let outgoingInserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "invites",
            filter: "sender_id=eq.\(userId.uuidString)"
        )
        let outgoingUpdates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "invites",
            filter: "sender_id=eq.\(userId.uuidString)"
        )

        await ch.subscribe()
        channel = ch

        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in inserts          { await MainActor.run { onInviteChange() } } }
                group.addTask { for await _ in updates          { await MainActor.run { onInviteChange() } } }
                group.addTask { for await _ in outgoingInserts  { await MainActor.run { onInviteChange() } } }
                group.addTask { for await _ in outgoingUpdates  { await MainActor.run { onInviteChange() } } }
                _ = self
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        if let channel { await channel.unsubscribe() }
        channel = nil
    }
}

/// Legacy stub kept for compatibility with earlier scaffolding.
final class RealtimeManager {
    static let shared = RealtimeManager()
    private init() {}

    func subscribeToInvites(receiverId: UUID,
                            onChange: @escaping (Invite) -> Void) {
        // Use RealtimeInviteManager.shared instead.
    }
    func subscribeToMessages(roomId: UUID,
                             onMessage: @escaping (Message) -> Void) {}
    func unsubscribeAll() {}
}
