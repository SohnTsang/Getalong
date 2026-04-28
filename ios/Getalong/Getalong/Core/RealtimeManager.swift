import Foundation
import Supabase

/// Subscribes to Supabase Realtime postgres-changes for the current
/// user's invites (both as receiver and sender) and fans events out to
/// any number of registered listeners. Callers refetch via PostgREST in
/// response.
///
/// Multi-subscriber design: one socket per signed-in user, regardless
/// of how many views care. The tab-bar tracker (MainTabView) keeps a
/// long-lived listener so the navbar tints update while the user is on
/// any tab; InvitesViewModel piggybacks on the same socket to refresh
/// its lists. Adding/removing listeners doesn't tear the channel down
/// — only `stop()` does, called when the user signs out.
@MainActor
final class RealtimeInviteManager {
    static let shared = RealtimeInviteManager()
    private init() {}

    typealias Listener = () -> Void

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?
    private var listeners: [UUID: Listener] = [:]
    private var attachedUserId: UUID?
    /// Serialises connect attempts. The first caller for a given user
    /// installs this; concurrent callers `await` it and skip their own
    /// connect. Without serialisation, two `addListener` calls at
    /// launch both pass the `attachedUserId == nil` check, both run
    /// `stop()` (clobbering each other's mid-flight subscribe) and
    /// both run `connect()` — yielding the "subscribe failed:
    /// CancellationError" + "Cannot add postgres_changes after
    /// subscribe" warnings we used to see at launch.
    private var connectTask: Task<Void, Never>?

    /// Register a listener for invite changes for `userId`. Returns a
    /// token; pass it back to `removeListener` when the caller goes
    /// away. The first call kicks off the channel; subsequent calls
    /// for the same userId reuse it.
    @discardableResult
    func addListener(userId: UUID, onChange: @escaping Listener) async -> UUID {
        // Wait for any in-flight connect (possibly for a different
        // user) to settle before deciding what to do.
        if let inflight = connectTask { await inflight.value }
        if attachedUserId != userId {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stop()
                await self.connect(userId: userId)
            }
            connectTask = task
            await task.value
            connectTask = nil
        }
        let token = UUID()
        listeners[token] = onChange
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
    }

    /// Back-compat for callers that want a one-shot start. Replaces any
    /// prior subscription and registers a single anonymous listener.
    func start(userId: UUID, onInviteChange: @escaping Listener) async {
        await stop()
        await connect(userId: userId)
        listeners[UUID()] = onInviteChange
    }

    private func connect(userId: UUID) async {
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
        attachedUserId = userId

        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in receiverInserts { await self?.fanout() } }
                group.addTask { for await _ in receiverUpdates { await self?.fanout() } }
                group.addTask { for await _ in senderInserts   { await self?.fanout() } }
                group.addTask { for await _ in senderUpdates   { await self?.fanout() } }
            }
        }
    }

    private func fanout() async {
        // Snapshot so a listener that removes itself mid-iteration
        // doesn't mutate the array under us.
        let snapshot = Array(listeners.values)
        for listener in snapshot { listener() }
    }

    func stop() async {
        task?.cancel()
        task = nil
        listeners.removeAll()
        attachedUserId = nil
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

/// App-wide subscription to chat_rooms inserts/updates for the current
/// user (sender or receiver side). Multi-listener like
/// RealtimeInviteManager — keeps a single websocket open from sign-in
/// until sign-out so the Chats list / unread state stay current no
/// matter which tab the user is on.
@MainActor
final class RealtimeChatRoomsManager {
    static let shared = RealtimeChatRoomsManager()
    private init() {}

    typealias Listener = () -> Void

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?
    private var listeners: [UUID: Listener] = [:]
    private var attachedUserId: UUID?
    private var connectTask: Task<Void, Never>?

    @discardableResult
    func addListener(userId: UUID, onChange: @escaping Listener) async -> UUID {
        if let inflight = connectTask { await inflight.value }
        if attachedUserId != userId {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stop()
                await self.connect(userId: userId)
            }
            connectTask = task
            await task.value
            connectTask = nil
        }
        let token = UUID()
        listeners[token] = onChange
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
    }

    private func connect(userId: UUID) async {
        let uid = userId.uuidString.lowercased()
        let ch = Supa.client.realtimeV2.channel("chat_rooms:user=\(uid)")

        let aInserts = ch.postgresChange(
            InsertAction.self, schema: "public", table: "chat_rooms",
            filter: .eq("user_a", value: uid)
        )
        let aUpdates = ch.postgresChange(
            UpdateAction.self, schema: "public", table: "chat_rooms",
            filter: .eq("user_a", value: uid)
        )
        let bInserts = ch.postgresChange(
            InsertAction.self, schema: "public", table: "chat_rooms",
            filter: .eq("user_b", value: uid)
        )
        let bUpdates = ch.postgresChange(
            UpdateAction.self, schema: "public", table: "chat_rooms",
            filter: .eq("user_b", value: uid)
        )

        do { try await ch.subscribeWithError() }
        catch {
            GALog.chat.error("realtime chat_rooms subscribe failed: \(error.localizedDescription)")
            return
        }
        channel = ch
        attachedUserId = userId

        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in aInserts { await self?.fanout() } }
                group.addTask { for await _ in aUpdates { await self?.fanout() } }
                group.addTask { for await _ in bInserts { await self?.fanout() } }
                group.addTask { for await _ in bUpdates { await self?.fanout() } }
            }
        }
    }

    private func fanout() async {
        let snapshot = Array(listeners.values)
        for listener in snapshot { listener() }
    }

    func stop() async {
        task?.cancel(); task = nil
        listeners.removeAll()
        attachedUserId = nil
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
