import Foundation
import Supabase

// MARK: - Shared realtime helpers

/// Subscribe-failure signal for the timeout-aware subscribe path.
enum RealtimeSubscribeError: Error { case timeout }

/// State labels for the explicit subscription FSM each manager exposes.
/// Logged on every transition with listener count + attempt number, so
/// it's obvious from the device log whether a hung subscribe got
/// retried, whether a stop was intentional, or whether listeners are
/// drifting on a dead channel.
enum RealtimeChannelState: String {
    case idle, subscribing, subscribed, failed, stopped
}

/// Run `ch.subscribeWithError()` with a hard timeout. supabase-swift's
/// realtime v2 has been observed to never resolve the subscribe await
/// (no error, no completion) when the auth socket re-establishes
/// mid-handshake — see Device A's "realtime chat subscribing …" log
/// without the matching "subscribed" follow-up. Without a timeout, the
/// whole channel sits dead forever and no retry path can fire, because
/// there's no thrown error to catch.
///
/// 5 s is generous: a healthy subscribe lands in ~150 ms; a slow
/// network blip resolves within 1–2 s; anything past 5 s is a hang and
/// we want to retry on a fresh channel rather than wait forever.
private let subscribeTimeoutSeconds: TimeInterval = 5

@MainActor
private func subscribeOrTimeout(_ ch: RealtimeChannelV2) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await ch.subscribeWithError() }
        group.addTask {
            try await Task.sleep(
                nanoseconds: UInt64(subscribeTimeoutSeconds * 1_000_000_000)
            )
            throw RealtimeSubscribeError.timeout
        }
        defer { group.cancelAll() }
        try await group.next()
    }
}

private func describe(_ error: Error) -> String {
    if error is RealtimeSubscribeError { return "timeout" }
    if error is CancellationError      { return "cancelled" }
    return "failed: \(error.localizedDescription)"
}

// MARK: - RealtimeInviteManager

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
    private var connectTask: Task<Void, Never>?
    private var subscribeRetryTask: Task<Void, Never>?

    /// Generation token. Incremented by every stop() so an in-flight
    /// connect that was racing the stop can detect it was intentionally
    /// torn down (and skip retry) rather than treat its CancellationError
    /// as a network blip.
    private var generation: UInt64 = 0

    private var state: RealtimeChannelState = .idle
    private func setState(_ s: RealtimeChannelState, attempt: Int = 0) {
        guard state != s else { return }
        GALog.invite.info("""
            realtime invite state \(self.state.rawValue, privacy: .public) -> \(s.rawValue, privacy: .public) \
            attempt=\(attempt, privacy: .public) listeners=\(self.listeners.count, privacy: .public)
            """)
        state = s
    }

    @discardableResult
    func addListener(userId: UUID, onChange: @escaping Listener) async -> UUID {
        if let inflight = connectTask { await inflight.value }
        if attachedUserId != userId {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stop()
                await self.connect(userId: userId, attempt: 0)
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
        await connect(userId: userId, attempt: 0)
        listeners[UUID()] = onInviteChange
    }

    private func connect(userId: UUID, attempt: Int) async {
        let myGen = generation
        setState(.subscribing, attempt: attempt)

        let uid = userId.uuidString.lowercased()
        let ch = Supa.client.realtimeV2.channel(
            "invites:user=\(uid):\(UUID().uuidString.prefix(8))"
        )

        let receiverInserts = ch.postgresChange(
            InsertAction.self, schema: "public", table: "invites",
            filter: .eq("receiver_id", value: uid)
        )
        let receiverUpdates = ch.postgresChange(
            UpdateAction.self, schema: "public", table: "invites",
            filter: .eq("receiver_id", value: uid)
        )
        let senderInserts = ch.postgresChange(
            InsertAction.self, schema: "public", table: "invites",
            filter: .eq("sender_id", value: uid)
        )
        let senderUpdates = ch.postgresChange(
            UpdateAction.self, schema: "public", table: "invites",
            filter: .eq("sender_id", value: uid)
        )

        GALog.invite.info("realtime invite subscribe start user=\(uid, privacy: .public) attempt=\(attempt, privacy: .public)")
        do {
            try await subscribeOrTimeout(ch)
        } catch {
            await Supa.client.realtimeV2.removeChannel(ch)
            // If our generation changed during subscribe, stop() ran.
            // Don't retry — the user is signing out / switching.
            guard myGen == generation else {
                GALog.invite.info("realtime invite subscribe aborted (intentional stop) attempt=\(attempt, privacy: .public)")
                return
            }
            GALog.invite.error("realtime invite subscribe \(describe(error), privacy: .public) attempt=\(attempt, privacy: .public)")
            setState(.failed, attempt: attempt)
            scheduleSubscribeRetry(userId: userId, attempt: attempt + 1)
            return
        }

        // Final guard: another stop() may have raced in between the
        // subscribe resolving and us reaching this line.
        guard myGen == generation else {
            await Supa.client.realtimeV2.removeChannel(ch)
            return
        }

        subscribeRetryTask?.cancel(); subscribeRetryTask = nil
        channel = ch
        attachedUserId = userId
        setState(.subscribed, attempt: attempt)

        // Tell listeners to do their initial / catch-up refresh.
        // The tracker's listener is `scheduleRefresh`, which is exactly
        // what we want on a fresh subscribe (and is idempotent).
        await fanout()

        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in receiverInserts { await self?.fanout() } }
                group.addTask { for await _ in receiverUpdates { await self?.fanout() } }
                group.addTask { for await _ in senderInserts   { await self?.fanout() } }
                group.addTask { for await _ in senderUpdates   { await self?.fanout() } }
            }
        }
    }

    private func scheduleSubscribeRetry(userId: UUID, attempt: Int) {
        guard attempt <= 5 else {
            GALog.invite.error("realtime invite subscribe retry: giving up after \(attempt - 1) attempts")
            return
        }
        let delaySec = pow(2.0, Double(attempt - 1))   // 1, 2, 4, 8, 16
        GALog.invite.info("realtime invite retry scheduled in \(delaySec, privacy: .public)s attempt=\(attempt, privacy: .public)")
        subscribeRetryTask?.cancel()
        let scheduledGen = generation
        subscribeRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.generation == scheduledGen else { return }   // stop() ran
            guard self.connectTask == nil else { return }
            guard self.attachedUserId == nil || self.attachedUserId == userId else { return }
            GALog.invite.info("realtime invite retry start attempt=\(attempt, privacy: .public)")
            let task: Task<Void, Never> = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.connect(userId: userId, attempt: attempt)
            }
            self.connectTask = task
            await task.value
            self.connectTask = nil
        }
    }

    private func fanout() async {
        let snapshot = Array(listeners.values)
        for listener in snapshot { listener() }
    }

    func stop() async {
        // Bump generation FIRST so any in-flight connect can detect
        // it was stopped (and skip retry).
        generation &+= 1
        setState(.stopped)
        task?.cancel(); task = nil
        subscribeRetryTask?.cancel(); subscribeRetryTask = nil
        listeners.removeAll()
        attachedUserId = nil
        if let channel { await Supa.client.realtimeV2.removeChannel(channel) }
        channel = nil
        setState(.idle)
    }
}

// MARK: - RealtimeChatManager (per-room messages + media)

/// Per-room realtime subscription covering both `messages` INSERTs and
/// `media_assets` UPDATEs. One websocket channel per room with the same
/// multi-listener + serialised-connect pattern as the invite/rooms
/// managers. Multiple views opening the same room share a single
/// channel; it stays attached as long as at least one listener is
/// registered.
///
/// Decoded payloads are delivered to listeners directly so the view
/// model doesn't need to refetch the whole page after every event —
/// inserts append in O(1) and view-once status flips propagate in
/// real time on both sides.
///
/// Required publications:
///  * `messages`     — migration 0021
///  * `media_assets` — migration 0022
@MainActor
final class RealtimeChatManager {
    static let shared = RealtimeChatManager()
    private init() {}

    enum Event {
        case messageInserted(Message?)
        case mediaUpdated(MediaAsset?)
        /// Fanned out the moment the channel reaches `.subscribed`.
        /// Listeners (the room view model) use this to run a single
        /// delta catch-up via `ChatService.fetchMessages(since:)` and
        /// pick up anything that landed during the subscribe window.
        case subscribed
    }

    typealias Listener = (Event) -> Void

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?
    private var listeners: [UUID: Listener] = [:]
    private var attachedRoomId: UUID?
    private var connectTask: Task<Void, Never>?
    private var subscribeRetryTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    private var state: RealtimeChannelState = .idle
    private func setState(_ s: RealtimeChannelState, room: String, attempt: Int = 0) {
        guard state != s else { return }
        GALog.chat.info("""
            realtime chat state \(self.state.rawValue, privacy: .public) -> \(s.rawValue, privacy: .public) \
            room=\(room, privacy: .public) attempt=\(attempt, privacy: .public) listeners=\(self.listeners.count, privacy: .public)
            """)
        state = s
    }

    @discardableResult
    func addListener(roomId: UUID, onEvent: @escaping Listener) async -> UUID {
        if let inflight = connectTask { await inflight.value }
        if attachedRoomId != roomId {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stop()
                await self.connect(roomId: roomId, attempt: 0)
            }
            connectTask = task
            await task.value
            connectTask = nil
        }
        let token = UUID()
        listeners[token] = onEvent
        // If the channel is already subscribed, give this new listener
        // an immediate `.subscribed` pulse so it can catch up. Otherwise
        // it would have to wait for the next real event.
        if state == .subscribed {
            onEvent(.subscribed)
        }
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
        // No auto-stop. Doing so racily tore the channel down: if the
        // user navigated back into the same chat (or SwiftUI rebuilt
        // ChatRoomView), `addListener` could fire before our queued
        // `stop()` Task ran, the new listener got registered against
        // an attachedRoomId we then cleared, and the next subscribe
        // ran on a stale cached channel — chat went silent until a
        // manual reload. Channel sticks until explicit `stop()` (sign
        // out) or until a different room reattaches.
    }

    private func connect(roomId: UUID, attempt: Int) async {
        let myGen = generation
        let rid = roomId.uuidString.lowercased()
        setState(.subscribing, room: rid, attempt: attempt)

        let ch = Supa.client.realtimeV2.channel(
            "chat:room=\(rid):\(UUID().uuidString.prefix(8))"
        )

        let messageInserts = ch.postgresChange(
            InsertAction.self, schema: "public", table: "messages",
            filter: .eq("room_id", value: rid)
        )
        let mediaUpdates = ch.postgresChange(
            UpdateAction.self, schema: "public", table: "media_assets",
            filter: .eq("room_id", value: rid)
        )

        GALog.chat.info("realtime chat subscribe start room=\(rid, privacy: .public) attempt=\(attempt, privacy: .public)")
        do {
            try await subscribeOrTimeout(ch)
        } catch {
            await Supa.client.realtimeV2.removeChannel(ch)
            guard myGen == generation else {
                GALog.chat.info("realtime chat subscribe aborted (intentional stop) room=\(rid, privacy: .public) attempt=\(attempt, privacy: .public)")
                return
            }
            GALog.chat.error("realtime chat subscribe \(describe(error), privacy: .public) room=\(rid, privacy: .public) attempt=\(attempt, privacy: .public)")
            setState(.failed, room: rid, attempt: attempt)
            scheduleSubscribeRetry(roomId: roomId, attempt: attempt + 1)
            return
        }

        guard myGen == generation else {
            await Supa.client.realtimeV2.removeChannel(ch)
            return
        }

        subscribeRetryTask?.cancel(); subscribeRetryTask = nil
        channel = ch
        attachedRoomId = roomId
        setState(.subscribed, room: rid, attempt: attempt)

        // Subscribe-success pulse. ChatRoomViewModel uses this as the
        // signal to run a single `catchUpMessages` against
        // ChatService.fetchMessages(since:) — picking up anything that
        // landed during the subscribe window without a 50-row reload.
        await fanout(.subscribed)

        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await action in messageInserts {
                        let msg = try? action.decodeRecord(
                            as: Message.self, decoder: Self.decoder
                        )
                        await self?.fanout(.messageInserted(msg))
                    }
                }
                group.addTask {
                    for await action in mediaUpdates {
                        let asset = try? action.decodeRecord(
                            as: MediaAsset.self, decoder: Self.decoder
                        )
                        await self?.fanout(.mediaUpdated(asset))
                    }
                }
            }
        }
    }

    private func fanout(_ event: Event) async {
        let snapshot = Array(listeners.values)
        for listener in snapshot { listener(event) }
    }

    private func scheduleSubscribeRetry(roomId: UUID, attempt: Int) {
        guard attempt <= 5 else {
            GALog.chat.error("realtime chat subscribe retry: giving up after \(attempt - 1) attempts room=\(roomId.uuidString.lowercased(), privacy: .public)")
            return
        }
        let delaySec = pow(2.0, Double(attempt - 1))
        GALog.chat.info("realtime chat retry scheduled in \(delaySec, privacy: .public)s attempt=\(attempt, privacy: .public) room=\(roomId.uuidString.lowercased(), privacy: .public)")
        subscribeRetryTask?.cancel()
        let scheduledGen = generation
        subscribeRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.generation == scheduledGen else { return }
            guard self.connectTask == nil else { return }
            guard self.attachedRoomId == nil || self.attachedRoomId == roomId else { return }
            GALog.chat.info("realtime chat retry start attempt=\(attempt, privacy: .public) room=\(roomId.uuidString.lowercased(), privacy: .public)")
            let task: Task<Void, Never> = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.connect(roomId: roomId, attempt: attempt)
            }
            self.connectTask = task
            await task.value
            self.connectTask = nil
        }
    }

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
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
        return d
    }()

    func stop() async {
        generation &+= 1
        let oldRoom = attachedRoomId?.uuidString.lowercased() ?? "-"
        setState(.stopped, room: oldRoom)
        task?.cancel(); task = nil
        subscribeRetryTask?.cancel(); subscribeRetryTask = nil
        listeners.removeAll()
        attachedRoomId = nil
        if let channel { await Supa.client.realtimeV2.removeChannel(channel) }
        channel = nil
        setState(.idle, room: oldRoom)
    }
}

// MARK: - RealtimeChatRoomsManager (chat-list updates)

/// App-wide subscription to chat_rooms inserts/updates for the current
/// user (sender or receiver side). Multi-listener like
/// RealtimeInviteManager — keeps a single websocket open from sign-in
/// until sign-out so the Chats list / unread state stay current no
/// matter which tab the user is on.
@MainActor
final class RealtimeChatRoomsManager {
    static let shared = RealtimeChatRoomsManager()
    private init() {}

    /// Decoded event for a chat-rooms postgres-change. Listeners
    /// receive the inserted/updated row directly so they can patch
    /// their cache in place — no full re-fetch needed for the common
    /// "a new message bumped last_message_at" case.
    ///
    /// `.roomUpserted(nil)` is also fanned out on subscribe success
    /// so listeners do their initial catch-up. ChatsViewModel handles
    /// nil by falling through to a full `refresh()`.
    enum Event {
        case roomUpserted(ChatRoom?)
    }

    typealias Listener = (Event) -> Void

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?
    private var listeners: [UUID: Listener] = [:]
    private var attachedUserId: UUID?
    private var connectTask: Task<Void, Never>?
    private var subscribeRetryTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    private var state: RealtimeChannelState = .idle
    private func setState(_ s: RealtimeChannelState, attempt: Int = 0) {
        guard state != s else { return }
        GALog.chat.info("""
            realtime chat_rooms state \(self.state.rawValue, privacy: .public) -> \(s.rawValue, privacy: .public) \
            attempt=\(attempt, privacy: .public) listeners=\(self.listeners.count, privacy: .public)
            """)
        state = s
    }

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
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
        return d
    }()

    @discardableResult
    func addListener(userId: UUID, onChange: @escaping Listener) async -> UUID {
        if let inflight = connectTask { await inflight.value }
        if attachedUserId != userId {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stop()
                await self.connect(userId: userId, attempt: 0)
            }
            connectTask = task
            await task.value
            connectTask = nil
        }
        let token = UUID()
        listeners[token] = onChange
        // If we're already subscribed, give this listener an immediate
        // refresh signal (matches the per-room manager's behaviour).
        if state == .subscribed {
            onChange(.roomUpserted(nil))
        }
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeValue(forKey: token)
    }

    private func connect(userId: UUID, attempt: Int) async {
        let myGen = generation
        setState(.subscribing, attempt: attempt)
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

        GALog.chat.info("realtime chat_rooms subscribe start user=\(uid, privacy: .public) attempt=\(attempt, privacy: .public)")
        do {
            try await subscribeOrTimeout(ch)
        } catch {
            await Supa.client.realtimeV2.removeChannel(ch)
            guard myGen == generation else {
                GALog.chat.info("realtime chat_rooms subscribe aborted (intentional stop) attempt=\(attempt, privacy: .public)")
                return
            }
            GALog.chat.error("realtime chat_rooms subscribe \(describe(error), privacy: .public) attempt=\(attempt, privacy: .public)")
            setState(.failed, attempt: attempt)
            scheduleSubscribeRetry(userId: userId, attempt: attempt + 1)
            return
        }

        guard myGen == generation else {
            await Supa.client.realtimeV2.removeChannel(ch)
            return
        }

        subscribeRetryTask?.cancel(); subscribeRetryTask = nil
        channel = ch
        attachedUserId = userId
        setState(.subscribed, attempt: attempt)
        // Subscribe-success pulse: triggers ChatsViewModel.refresh()
        // (its applyRealtimeEvent treats `.roomUpserted(nil)` as a
        // full refresh). Ensures the chat list is current immediately
        // after a fresh subscribe.
        await fanout(.roomUpserted(nil))

        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await action in aInserts {
                        let room = try? action.decodeRecord(
                            as: ChatRoom.self, decoder: Self.decoder
                        )
                        await self?.fanout(.roomUpserted(room))
                    }
                }
                group.addTask {
                    for await action in aUpdates {
                        let room = try? action.decodeRecord(
                            as: ChatRoom.self, decoder: Self.decoder
                        )
                        await self?.fanout(.roomUpserted(room))
                    }
                }
                group.addTask {
                    for await action in bInserts {
                        let room = try? action.decodeRecord(
                            as: ChatRoom.self, decoder: Self.decoder
                        )
                        await self?.fanout(.roomUpserted(room))
                    }
                }
                group.addTask {
                    for await action in bUpdates {
                        let room = try? action.decodeRecord(
                            as: ChatRoom.self, decoder: Self.decoder
                        )
                        await self?.fanout(.roomUpserted(room))
                    }
                }
            }
        }
    }

    private func scheduleSubscribeRetry(userId: UUID, attempt: Int) {
        guard attempt <= 5 else {
            GALog.chat.error("realtime chat_rooms subscribe retry: giving up after \(attempt - 1) attempts")
            return
        }
        let delaySec = pow(2.0, Double(attempt - 1))
        GALog.chat.info("realtime chat_rooms retry scheduled in \(delaySec, privacy: .public)s attempt=\(attempt, privacy: .public)")
        subscribeRetryTask?.cancel()
        let scheduledGen = generation
        subscribeRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.generation == scheduledGen else { return }
            guard self.connectTask == nil else { return }
            guard self.attachedUserId == nil || self.attachedUserId == userId else { return }
            GALog.chat.info("realtime chat_rooms retry start attempt=\(attempt, privacy: .public)")
            let task: Task<Void, Never> = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.connect(userId: userId, attempt: attempt)
            }
            self.connectTask = task
            await task.value
            self.connectTask = nil
        }
    }

    private func fanout(_ event: Event) async {
        let snapshot = Array(listeners.values)
        for listener in snapshot { listener(event) }
    }

    func stop() async {
        generation &+= 1
        setState(.stopped)
        task?.cancel(); task = nil
        subscribeRetryTask?.cancel(); subscribeRetryTask = nil
        listeners.removeAll()
        attachedUserId = nil
        if let channel { await Supa.client.realtimeV2.removeChannel(channel) }
        channel = nil
        setState(.idle)
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
