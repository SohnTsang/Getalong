import Foundation
import Supabase

/// Subscribes to Supabase Realtime postgres-changes for the current user's
/// invites (both as receiver and sender) and fires a closure on any
/// change. Callers refetch via PostgREST in response.
@MainActor
final class RealtimeInviteManager {
    static let shared = RealtimeInviteManager()
    private init() {}

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?

    /// Begin listening. Replaces any prior subscription.
    func start(userId: UUID, onInviteChange: @escaping () -> Void) async {
        await stop()

        let uid = userId.uuidString.lowercased()
        let ch = Supa.client.realtimeV2.channel("invites:user=\(uid)")

        let receiverInserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "invites",
            filter: .eq("receiver_id", value: uid)
        )
        let receiverUpdates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "invites",
            filter: .eq("receiver_id", value: uid)
        )
        let senderInserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "invites",
            filter: .eq("sender_id", value: uid)
        )
        let senderUpdates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "invites",
            filter: .eq("sender_id", value: uid)
        )

        do {
            try await ch.subscribeWithError()
        } catch {
            GALog.invite.error("realtime subscribe failed: \(error.localizedDescription)")
            return
        }
        channel = ch

        task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in receiverInserts { await MainActor.run { onInviteChange() } } }
                group.addTask { for await _ in receiverUpdates { await MainActor.run { onInviteChange() } } }
                group.addTask { for await _ in senderInserts   { await MainActor.run { onInviteChange() } } }
                group.addTask { for await _ in senderUpdates   { await MainActor.run { onInviteChange() } } }
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

/// Subscribes to message inserts for a single chat room.
@MainActor
final class RealtimeChatManager {
    static let shared = RealtimeChatManager()
    private init() {}

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?

    func start(roomId: UUID, onInsert: @escaping () -> Void) async {
        await stop()
        let rid = roomId.uuidString.lowercased()
        let ch = Supa.client.realtimeV2.channel("chat:room=\(rid)")

        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: .eq("room_id", value: rid)
        )

        do { try await ch.subscribeWithError() }
        catch {
            GALog.chat.error("realtime chat subscribe failed: \(error.localizedDescription)")
            return
        }
        channel = ch

        task = Task {
            for await _ in inserts {
                await MainActor.run { onInsert() }
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
                             onMessage: @escaping (Message) -> Void) {
        // Use RealtimeChatManager.shared instead.
    }
    func unsubscribeAll() {}
}
