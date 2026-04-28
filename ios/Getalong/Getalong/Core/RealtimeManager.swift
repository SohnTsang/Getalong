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
        // Channel topic carries a per-attempt UUID so a previous
        // failed subscribe (CancellationError, network blip, etc.)
        // can never leave a cached half-subscribed channel under a
        // stable name. The supabase-swift SDK caches channels by
        // topic; without uniqueness the next connect would reuse the
        // stale instance and `postgresChange` would print
        // "Cannot add postgres_changes after subscribe()".
        let uid = userId.uuidString.lowercased()
        let ch = Supa.client.realtimeV2.channel(
            "invites:user=\(uid):\(UUID().uuidString.prefix(8))"
        )

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
            // Release the half-subscribed channel from the SDK cache
            // so a retry doesn't reuse it.
            await Supa.client.realtimeV2.removeChannel(ch)
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
        // removeChannel both unsubscribes AND drops the entry from the
        // SDK's name->channel cache. unsubscribe() alone leaves the
        // entry, which is what produced the "after subscribe()" warnings.
        if let channel { await Supa.client.realtimeV2.removeChannel(channel) }
        channel = nil
    }
}

/// Per-room message INSERT subscription with the same multi-listener
/// + serialised-connect pattern as the invite/rooms managers. Multiple
/// views opening the same room share a single websocket; the channel
/// stays attached as long as at least one listener is registered.
///
/// Important: `messages` must be in the `supabase_realtime` publication
/// (see migration 0021) — otherwise subscribe succeeds but no events
/// ever fire and chat shows new rows only after a manual refresh.
@MainActor
final class RealtimeChatManager {
    static let shared = RealtimeChatManager()
    private init() {}

    typealias Listener = () -> Void

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?
    private var listeners: [UUID: Listener] = [:]
    private var attachedRoomId: UUID?
    private var connectTask: Task<Void, Never>?

    @discardableResult
    func addListener(roomId: UUID, onInsert: @escaping Listener) async -> UUID {
        if let inflight = connectTask { await inflight.value }
        if attachedRoomId != roomId {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stop()
                await self.connect(roomId: roomId)
            }
            connectTask = task
            await task.value
            connectTask = nil
        }
        let token = UUID()
        listeners[token] = onInsert
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        // Tear the channel down once the last listener is gone — saves
        // a websocket while the user isn't in any room.
        if listeners.isEmpty {
            Task { @MainActor [weak self] in await self?.stop() }
        }
    }

    private func connect(roomId: UUID) async {
        let rid = roomId.uuidString.lowercased()
        let ch = Supa.client.realtimeV2.channel(
            "chat:room=\(rid):\(UUID().uuidString.prefix(8))"
        )

        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: .eq("room_id", value: rid)
        )

        do { try await ch.subscribeWithError() }
        catch {
            GALog.chat.error("realtime chat subscribe failed: \(error.localizedDescription)")
            await Supa.client.realtimeV2.removeChannel(ch)
            return
        }
        channel = ch
        attachedRoomId = roomId

        task = Task { [weak self] in
            for await _ in inserts {
                await self?.fanout()
            }
        }
    }

    private func fanout() async {
        let snapshot = Array(listeners.values)
        for listener in snapshot { listener() }
    }

    func stop() async {
        task?.cancel()
        task = nil
        listeners.removeAll()
        attachedRoomId = nil
        if let channel { await Supa.client.realtimeV2.removeChannel(channel) }
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
        let ch = Supa.client.realtimeV2.channel(
            "chat_rooms:user=\(uid):\(UUID().uuidString.prefix(8))"
        )

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
            await Supa.client.realtimeV2.removeChannel(ch)
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
        if let channel { await Supa.client.realtimeV2.removeChannel(channel) }
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
