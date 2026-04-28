import Foundation
import SwiftUI

@MainActor
final class ChatRoomViewModel: ObservableObject {

    let roomId: UUID
    private(set) var partner: Profile?
    private(set) var currentUserId: UUID?

    @Published var messages: [Message] = []
    /// Asset cache keyed by media_id, populated lazily when rendering media bubbles.
    @Published var mediaAssets: [UUID: MediaAsset] = [:]
    /// Local-only cache: the sender's own thumbnails keyed by media_id,
    /// kept in memory for the lifetime of this view so the sender can see
    /// a blurred version of what they sent. Bytes never reach the
    /// receiver; this dictionary is only ever populated from the local
    /// `MediaUploadController.thumbnail`.
    @Published var localMediaThumbnails: [UUID: UIImage] = [:]
    @Published var isLoadingInitial: Bool = true
    @Published var loadError: String?
    @Published var sendError: String?
    @Published var isSending: Bool = false
    @Published var draft: String = ""

    /// Composer for the in-flight piece of view-once media. nil when idle.
    @Published var mediaController: MediaUploadController?
    /// Drives the fullscreen preview separately from the controller's
    /// lifetime so that tapping Send can close the preview *immediately*
    /// while upload+send continues in the background.
    @Published var isPreviewPresented: Bool = false

    /// Local optimistic bubbles for media that's been Sent from the
    /// preview but hasn't yet been confirmed by the server. They render
    /// as outgoing image bubbles with a subtle progress overlay; on
    /// success we drop the entry and append the real Message; on
    /// failure we leave it with a retry chip.
    @Published var pendingMedia: [PendingMediaItem] = []

    struct PendingMediaItem: Identifiable, Equatable {
        let id: UUID
        let thumbnail: UIImage?
        var state: State

        enum State: Equatable {
            case sending
            case failed(message: String)
        }

        static func == (lhs: PendingMediaItem, rhs: PendingMediaItem) -> Bool {
            lhs.id == rhs.id && lhs.state == rhs.state
        }
    }

    /// id of media currently being viewed (full-screen sheet).
    @Published var openingMediaId: UUID?
    /// Cached message type for the opening sheet (drives gif/video/image render).
    @Published var openingMessageType: MessageType?

    // MARK: - Safety

    @Published var hasBlockedPartner: Bool = false
    @Published var safetyError: String?
    @Published var blockSuccessFeedback: Bool = false

    /// Active report context (if any). The view presents a sheet when set.
    @Published var pendingReport: ReportContext?
    /// True when the block confirmation sheet is presented.
    @Published var isBlockConfirmPresented: Bool = false
    /// True while the .confirmationDialog for "Delete conversation" is open.
    @Published var isDeleteConfirmPresented: Bool = false
    /// In-flight indicator for the delete-conversation network call.
    @Published var isDeleting: Bool = false
    /// Set to true when the conversation has been successfully deleted —
    /// the view dismisses itself back to ChatsView when this flips.
    @Published var didDelete: Bool = false
    /// Localized error from the most recent failed delete attempt.
    @Published var deleteError: String?

    /// Realtime token for the app-wide chat_rooms manager. Released on
    /// detach. We use it to auto-bounce the partner if the other user
    /// leaves the chat while we have it open.
    private var roomsListenerToken: UUID?
    /// Realtime token for the per-room messages INSERT stream.
    private var messagesListenerToken: UUID?
    /// Belt-and-braces polling task. Realtime is the primary signal,
    /// but if the websocket misses an event (filter mismatch, RLS
    /// quirk, transient disconnect) we still want messages to appear
    /// without the user backing out and re-entering. 4-second tick is
    /// fast enough to feel near-instant while costing one cheap
    /// fetchMessages per room per interval.
    private var fallbackPollTask: Task<Void, Never>?

    struct ReportContext: Identifiable, Equatable {
        let id = UUID()
        let targetType: ReportTargetType
        let targetId: UUID
    }

    init(roomId: UUID, partner: Profile?) {
        self.roomId = roomId
        self.partner = partner
    }

    func attach(currentUserId: UUID) async {
        self.currentUserId = currentUserId
        // Mark the user as present in this room so the push delegate
        // can suppress banners for incoming messages from this chat.
        ChatPresence.shared.enter(roomId)
        // Opening the room counts as "I've seen everything up to now".
        ChatReadState.shared.markRead(roomId)

        if partner == nil {
            if let room = try? await ChatService.shared.fetchRoom(id: roomId) {
                partner = try? await ChatService.shared.fetchPartnerProfile(
                    for: room, currentUserId: currentUserId)
            }
        }

        await refreshBlockState()
        await reload()

        // Subscribing must outlive SwiftUI's .task body — that body's
        // Task gets cancelled on every view re-render, and Task
        // cancellation propagates into await chains, which would tear
        // down `subscribeWithError` mid-handshake. Spawn unstructured
        // Tasks so the realtime sockets survive the view churn.
        Task { [weak self, roomId] in
            guard let self else { return }
            GALog.chat.info("ChatRoomVM addListener start room=\(roomId.uuidString, privacy: .public)")
            let token = await RealtimeChatManager.shared.addListener(
                roomId: roomId
            ) { [weak self] event in
                Task { @MainActor in await self?.handleRealtime(event: event) }
            }
            await MainActor.run {
                self.messagesListenerToken = token
                GALog.chat.info("ChatRoomVM addListener ok token=\(token.uuidString.prefix(8), privacy: .public)")
            }
        }

        Task { [weak self, currentUserId] in
            guard let self else { return }
            let token = await RealtimeChatRoomsManager.shared.addListener(
                userId: currentUserId
            ) { [weak self] in
                Task { @MainActor in await self?.checkRoomActive() }
            }
            await MainActor.run { self.roomsListenerToken = token }
        }

        startFallbackPolling()
    }

    private func startFallbackPolling() {
        fallbackPollTask?.cancel()
        fallbackPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.reloadOnRealtimeInsert()
            }
        }
    }

    /// Re-fetches the room status and flips `didDelete` to true if the
    /// other side has left (status != 'active'). The view is bound to
    /// `didDelete` and dismisses itself back to ChatsView automatically.
    private func checkRoomActive() async {
        guard !didDelete else { return }
        guard let room = try? await ChatService.shared.fetchRoom(id: roomId) else { return }
        if room.status != .active {
            didDelete = true
            mediaController?.cancel()
            mediaController = nil
        }
    }

    func refreshBlockState() async {
        guard let me = currentUserId, let p = partner else { return }
        hasBlockedPartner = await ReportService.shared.hasBlocked(userId: p.id, by: me)
    }

    // MARK: - Safety actions

    func presentReportUser() {
        guard let p = partner else { return }
        pendingReport = .init(targetType: .profile, targetId: p.id)
    }

    func presentReportMessage(_ message: Message) {
        pendingReport = .init(targetType: .message, targetId: message.id)
    }

    func presentReportMedia(mediaId: UUID) {
        pendingReport = .init(targetType: .media, targetId: mediaId)
    }

    func presentBlockConfirm() {
        isBlockConfirmPresented = true
    }

    /// Show the system confirmationDialog. The actual delete fires only
    /// when the user taps the destructive action.
    func presentDeleteConfirm() {
        isDeleteConfirmPresented = true
    }

    func confirmDeleteConversation() async {
        guard !isDeleting && !didDelete else { return }
        isDeleting = true
        defer { isDeleting = false }
        deleteError = nil
        do {
            _ = try await ChatService.shared.deleteConversation(roomId: roomId)
            didDelete = true
            Haptics.success()
        } catch let e as ChatServiceError {
            deleteError = e.errorDescription
            Haptics.error()
        } catch {
            deleteError = String(localized: "chat.delete.error")
            Haptics.error()
        }
    }

    func confirmedBlock() async {
        // BlockUserSheet already called the backend successfully; just
        // reflect locally and tear down any in-flight composer.
        hasBlockedPartner = true
        isBlockConfirmPresented = false
        blockSuccessFeedback = true
        mediaController?.cancel()
        mediaController = nil
        await refreshBlockState()
    }

    func detach() async {
        ChatPresence.shared.leave(roomId)
        fallbackPollTask?.cancel()
        fallbackPollTask = nil
        if let token = messagesListenerToken {
            RealtimeChatManager.shared.removeListener(token)
            messagesListenerToken = nil
        }
        if let token = roomsListenerToken {
            RealtimeChatRoomsManager.shared.removeListener(token)
            roomsListenerToken = nil
        }
        mediaController?.cancel()
        mediaController = nil
    }

    // MARK: - Loads

    func reload() async {
        do {
            messages = try await ChatService.shared.fetchMessages(roomId: roomId, limit: 50)
            await hydrateMediaAssets()
            loadError = nil
        } catch {
            loadError = String(localized: "chat.error.loadFailed")
        }
        isLoadingInitial = false
    }

    /// Realtime events deliver the changed row directly so we can
    /// append/refresh in O(1) — no 50-message refetch on every event.
    /// On a decode failure we fall back to the full reload path so a
    /// schema mismatch can never make the chat go silent.
    private func handleRealtime(event: RealtimeChatManager.Event) async {
        switch event {
        case .messageInserted(let msg):
            if let msg, msg.roomId == roomId {
                if !messages.contains(where: { $0.id == msg.id }) {
                    messages.append(msg)
                }
                if let mid = msg.mediaId, mediaAssets[mid] == nil {
                    if let asset = try? await MediaService.shared.fetchAsset(id: mid) {
                        mediaAssets[mid] = asset
                    }
                }
                // We're inside the room when the message arrived, so
                // it's seen the moment it appears — no unread dot.
                ChatReadState.shared.markRead(roomId, at: msg.createdAt)
            } else {
                await reloadOnRealtimeInsert()
            }
        case .mediaUpdated(let asset):
            if let asset, asset.roomId == roomId {
                mediaAssets[asset.id] = asset
            }
        }
    }

    private func reloadOnRealtimeInsert() async {
        GALog.chat.info("realtime reload start room=\(self.roomId.uuidString, privacy: .public)")
        do {
            let latest = try await ChatService.shared.fetchMessages(roomId: roomId, limit: 50)
            messages = latest
            await hydrateMediaAssets()
            GALog.chat.info("realtime reload ok count=\(latest.count, privacy: .public)")
        } catch {
            GALog.chat.error("realtime reload: \(error.localizedDescription)")
        }
    }

    /// Loads media metadata for any message whose media_id is not yet in
    /// the cache. Best-effort; failures stay silent so chat still renders.
    private func hydrateMediaAssets() async {
        let needed = messages
            .compactMap { $0.mediaId }
            .filter { mediaAssets[$0] == nil }
        for id in Set(needed) {
            if let asset = try? await MediaService.shared.fetchAsset(id: id) {
                mediaAssets[id] = asset
            }
        }
    }

    // MARK: - Send (text)

    var canSend: Bool {
        !hasBlockedPartner
        && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isSending
    }

    var canAttachMedia: Bool {
        !hasBlockedPartner && mediaController == nil && !isSending
    }

    /// True while at least one optimistic bubble is uploading. Used to
    /// disable the attach button so we never queue a second pick on top
    /// of an in-flight one (the controller is single-use).
    var hasInFlightMedia: Bool {
        pendingMedia.contains { if case .sending = $0.state { return true } else { return false } }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isSending else { return }
        sendError = nil
        isSending = true
        defer { isSending = false }

        do {
            let inserted = try await ChatService.shared.sendTextMessage(roomId: roomId, body: text)
            if !messages.contains(where: { $0.id == inserted.id }) {
                messages.append(inserted)
            }
            draft = ""
            Haptics.tap()
        } catch let e as ChatServiceError {
            sendError = e.errorDescription
            Haptics.error()
            // If the backend rejected with BLOCKED_RELATIONSHIP, our local
            // view of the block state is stale — most likely the partner
            // blocked us. Re-check so the input flips to the blocked card.
            if e == .blockedRelationship {
                await refreshBlockState()
            }
            // Other side left the chat; bounce back to Chats so we
            // don't sit in a dead room. The realtime listener usually
            // fires first, but this is the belt-and-braces path for
            // the case where the user hits Send before the row update
            // has propagated to our socket.
            if e == .roomNotActive || e == .roomNotFound {
                didDelete = true
            }
        } catch {
            sendError = String(localized: "chat.error.sendFailed")
            Haptics.error()
        }
    }

    // MARK: - Send (media)

    func startMediaPick(_ source: MediaUploadController.PickerSource) {
        // Prepare-only — opens a fullscreen preview (MediaPreviewSheet)
        // where the user reviews the picked image and taps Send.
        // Upload + send don't fire until they tap Send.
        let controller = MediaController(roomId: roomId)
        mediaController = controller
        isPreviewPresented = true
        controller.begin(source)
    }

    /// User tapped Send in the preview. Close the preview immediately,
    /// drop a local optimistic bubble into the chat (so it feels like a
    /// normal chat app), and run upload+send in the background.
    func confirmMediaSend() {
        guard let controller = mediaController else { return }
        let thumb = controller.thumbnail
        let item = PendingMediaItem(
            id: UUID(),
            thumbnail: thumb,
            state: .sending
        )
        pendingMedia.append(item)
        isPreviewPresented = false
        Haptics.tap()

        controller.confirmSend { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.pendingMedia.removeAll { $0.id == item.id }
                // Cache the sender's local thumbnail unconditionally —
                // the realtime INSERT can race the send response and
                // hydrate `messages` (via reloadOnRealtimeInsert)
                // before this onSuccess fires. If we gated the
                // thumbnail cache on "wasn't already in messages",
                // the bubble would lose its blurred backdrop and
                // fall back to the abstract orange placeholder.
                if let mid = message.mediaId {
                    if let thumb { self.localMediaThumbnails[mid] = thumb }
                    if let asset = try? await MediaService.shared.fetchAsset(id: mid) {
                        self.mediaAssets[mid] = asset
                    }
                }
                if !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.append(message)
                }
                self.mediaController = nil
            }
        }

        watchPendingMedia(itemId: item.id, controller: controller)
    }

    /// Polls the controller's state until upload+send terminates and
    /// flips the optimistic bubble to .failed if the controller reports
    /// an error. The success path is owned by `confirmSend`'s onSuccess
    /// closure (it removes the bubble); this watcher just handles the
    /// failure half so we don't have to plumb errors back through the
    /// callback shape.
    private func watchPendingMedia(itemId: UUID, controller: MediaUploadController) {
        Task { @MainActor [weak self, weak controller] in
            guard let self, let controller else { return }
            // First wait for the controller to leave .readyPreview —
            // otherwise we'd see the initial state and bail before
            // upload begins.
            while !Task.isCancelled {
                if case .readyPreview = controller.state {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    continue
                }
                break
            }
            while !Task.isCancelled {
                switch controller.state {
                case .failedBeforeUpload(let m), .failedAfterUpload(let m, _):
                    self.updatePending(id: itemId, state: .failed(message: m))
                    return
                case .idle:
                    // success path already removed the bubble.
                    return
                default:
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
        }
    }

    private func updatePending(id: UUID, state: PendingMediaItem.State) {
        guard let idx = pendingMedia.firstIndex(where: { $0.id == id }) else { return }
        var item = pendingMedia[idx]
        item.state = state
        pendingMedia[idx] = item
    }

    /// User retried a failed pending bubble. The underlying controller
    /// already knows whether it can skip re-upload (failedAfterUpload) or
    /// must re-prepare (failedBeforeUpload); we just toggle the bubble
    /// back to .sending and rewire the success/failure observer.
    func retryPendingMedia(_ id: UUID) {
        guard let controller = mediaController else { return }
        let thumb = controller.thumbnail
        updatePending(id: id, state: .sending)
        controller.retry { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.pendingMedia.removeAll { $0.id == id }
                if let mid = message.mediaId {
                    if let thumb { self.localMediaThumbnails[mid] = thumb }
                    if let asset = try? await MediaService.shared.fetchAsset(id: mid) {
                        self.mediaAssets[mid] = asset
                    }
                }
                if !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.append(message)
                }
                self.mediaController = nil
            }
        }
        watchPendingMedia(itemId: id, controller: controller)
    }

    /// Drops a failed bubble. The orphaned media row (if any) is reaped
    /// server-side by deleteExpiredMedia within 30 minutes.
    func removePendingMedia(_ id: UUID) {
        pendingMedia.removeAll { $0.id == id }
        if pendingMedia.isEmpty {
            mediaController?.cancel()
            mediaController = nil
        }
    }

    func dismissMediaComposer() {
        // Only invoked when the user closes the preview without sending.
        // If a Send already happened the preview is already gone and
        // mediaController stays alive until the background task finishes.
        isPreviewPresented = false
        if !hasInFlightMedia {
            mediaController?.cancel()
            mediaController = nil
        }
    }

    // MARK: - Open view-once

    func openMedia(_ message: Message) {
        guard let mid = message.mediaId else { return }
        guard let asset = mediaAssets[mid] else { return }
        guard !isMine(message),
              asset.viewOnce,
              asset.status == .active,
              asset.viewedAt == nil
        else { return }
        openingMediaId = mid
        openingMessageType = message.messageType
    }

    /// Called by the viewer when it has confirmed the server flipped the
    /// row to viewed (or it was already viewed). We update the local cache
    /// so the bubble shows the correct state immediately.
    func markLocalAssetViewed(_ mediaId: UUID) {
        guard var asset = mediaAssets[mediaId] else { return }
        asset.status = .viewed
        asset.viewedAt = Date()
        asset.viewedBy = currentUserId
        mediaAssets[mediaId] = asset
    }

    func closeMediaViewer() {
        // After close: the viewer has fired finalizeViewOnceMedia (server
        // deletes the storage object immediately). Stamp the local cache
        // so the bubble shows "No longer available" right away, then
        // refresh from the server so the canonical state is reflected
        // (sender bubble, etc.).
        if let id = openingMediaId, var asset = mediaAssets[id] {
            asset.storageDeletedAt = Date()
            mediaAssets[id] = asset
            Task {
                if let updated = try? await MediaService.shared.fetchAsset(id: id) {
                    mediaAssets[id] = updated
                }
            }
        }
        openingMediaId = nil
        openingMessageType = nil
    }

    // MARK: - Display helpers

    func isMine(_ message: Message) -> Bool {
        message.senderId == currentUserId
    }

    func mediaAsset(for message: Message) -> MediaAsset? {
        message.mediaId.flatMap { mediaAssets[$0] }
    }

    /// Sender's own local thumbnail for the given message. Returns nil
    /// for the receiver's bubbles — they never see image bytes until
    /// they tap to open.
    func localThumbnail(for message: Message) -> UIImage? {
        guard isMine(message), let mid = message.mediaId else { return nil }
        return localMediaThumbnails[mid]
    }

    var headerTitle: String {
        partner?.displayName.isEmpty == false
            ? partner!.displayName
            : String(localized: "chat.title.fallback")
    }

    var headerSubtitle: String? {
        partner.map { "@\($0.getalongId)" }
    }

    /// Single-line representation of the partner used in the header
    /// and chat-list rows. Falls back to a quiet placeholder when the
    /// partner hasn't written one. No display name, no handle —
    /// Getalong identifies people by their line.
    var headerLine: String {
        if let bio = partner?.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bio.isEmpty {
            return bio
        }
        return String(localized: "chat.title.fallback")
    }
}

// MARK: - typealias

typealias MediaController = MediaUploadController
