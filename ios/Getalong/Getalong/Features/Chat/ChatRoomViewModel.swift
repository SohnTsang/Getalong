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
    @Published var isLoadingInitial: Bool = true
    @Published var loadError: String?
    @Published var sendError: String?
    @Published var isSending: Bool = false
    @Published var draft: String = ""

    /// Composer for the in-flight piece of view-once media. nil when idle.
    @Published var mediaController: MediaUploadController?

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

        if partner == nil {
            if let room = try? await ChatService.shared.fetchRoom(id: roomId) {
                partner = try? await ChatService.shared.fetchPartnerProfile(
                    for: room, currentUserId: currentUserId)
            }
        }

        await refreshBlockState()
        await reload()

        await RealtimeChatManager.shared.start(roomId: roomId) { [weak self] in
            Task { await self?.reloadOnRealtimeInsert() }
        }
    }

    private func refreshBlockState() async {
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
        await RealtimeChatManager.shared.stop()
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

    private func reloadOnRealtimeInsert() async {
        do {
            let latest = try await ChatService.shared.fetchMessages(roomId: roomId, limit: 50)
            messages = latest
            await hydrateMediaAssets()
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
        } catch {
            sendError = String(localized: "chat.error.sendFailed")
            Haptics.error()
        }
    }

    // MARK: - Send (media)

    func startMediaPick(_ source: MediaUploadController.PickerSource) {
        let controller = MediaController(roomId: roomId)
        mediaController = controller
        controller.begin(source)
    }

    func confirmMediaSend() {
        guard let controller = mediaController else { return }
        controller.confirmSend { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                if !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.append(message)
                    if let mid = message.mediaId,
                       let asset = try? await MediaService.shared.fetchAsset(id: mid) {
                        self.mediaAssets[mid] = asset
                    }
                }
                self.mediaController = nil
                Haptics.tap()
            }
        }
    }

    func dismissMediaComposer() {
        mediaController?.cancel()
        mediaController = nil
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

    var headerTitle: String {
        partner?.displayName.isEmpty == false
            ? partner!.displayName
            : String(localized: "chat.title.fallback")
    }

    var headerSubtitle: String? {
        partner.map { "@\($0.getalongId)" }
    }
}

// MARK: - typealias

typealias MediaController = MediaUploadController
