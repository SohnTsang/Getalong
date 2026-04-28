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
    /// Set synchronously at the top of `connect()` so a concurrent
    /// `addListener` won't kick off a second connect for the same user
    /// while the first is still awaiting `subscribeWithError`. Without
    /// this guard, two listeners attaching during launch each ran
    /// connect → both got the SDK-cached channel back → the second
    /// call's 4 `postgresChange` registrations landed after subscribe
    /// and the SDK printed "Cannot add postgres_changes after subscribe".
    private var connectingUserId: UUID?

    /// Register a listener for invite changes for `userId`. Returns a
    /// token; pass it back to `removeListener` when the caller goes
    /// away. The first call kicks off the channel; subsequent calls
    /// for the same userId reuse it.
    @discardableResult
    func addListener(userId: UUID, onChange: @escaping Listener) async -> UUID {
        // Connect only when this is a brand-new user AND no other
        // attach is already in flight for the same user. Both checks
        // matter: `attachedUserId` is set after subscribe completes,
        // `connectingUserId` is set synchronously at the top of
        // connect() — together they cover the racy "two attaches at
        // launch" case.
        if attachedUserId != userId && connectingUserId != userId {
            await stop()
            await connect(userId: userId)
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
        // Mark the connect attempt up front so a concurrent caller
        // sees the in-flight intent and skips its own connect.
        connectingUserId = userId
        defer { if connectingUserId == userId { connectingUserId = nil } }

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
        connectingUserId = nil
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
    private var connectingUserId: UUID?

    @discardableResult
    func addListener(userId: UUID, onChange: @escaping Listener) async -> UUID {
        if attachedUserId != userId && connectingUserId != userId {
            await stop()
            await connect(userId: userId)
        }
        let token = UUID()
        listeners[token] = onChange
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
    }

    private func connect(userId: UUID) async {
        connectingUserId = userId
        defer { if connectingUserId == userId { connectingUserId = nil } }

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
        connectingUserId = nil
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
