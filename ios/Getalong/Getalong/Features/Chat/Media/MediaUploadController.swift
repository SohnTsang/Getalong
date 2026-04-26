import Foundation
import SwiftUI

/// State machine for sending one piece of view-once media.
///
///   idle → preparing → readyPreview → uploading → sending → sent
///                                          ↓          ↓
///                                       failed     failed (after upload)
///                                          ↓
///                                       retry / cancel
///
/// `failedAfterUpload` carries the existing `mediaId` so a retry can re-call
/// createChatMessage without re-uploading. If the user picks Remove instead
/// of Retry, we leave the orphaned media row to be cleaned up by
/// deleteExpiredMedia.
@MainActor
final class MediaUploadController: ObservableObject {

    enum State: Equatable {
        case idle
        case preparing
        case readyPreview
        case uploading
        case sending
        case failedBeforeUpload(message: String)
        case failedAfterUpload(message: String, mediaId: UUID)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var prepared: MediaPreparedFile?
    @Published private(set) var thumbnail: UIImage?
    /// Caption is currently unused (composer keeps it for forward-compat).
    @Published var caption: String = ""

    private let roomId: UUID
    private var pickedSource: PickerSource?
    private var workTask: Task<Void, Never>?
    private var uploadTicket: MediaService.UploadTicket?

    init(roomId: UUID) {
        self.roomId = roomId
    }

    deinit { workTask?.cancel() }

    enum PickerSource: Equatable {
        case imageData(Data, sourceMime: String?)
        case videoFile(URL)
    }

    var canCancel: Bool {
        switch state {
        case .preparing, .uploading, .sending, .readyPreview: return true
        default: return false
        }
    }

    var canRetry: Bool {
        switch state {
        case .failedBeforeUpload, .failedAfterUpload: return true
        default: return false
        }
    }

    var stateLabel: String {
        switch state {
        case .preparing:               return String(localized: "media.preparing")
        case .uploading:               return String(localized: "media.uploading")
        case .sending:                 return String(localized: "media.sending")
        case .failedBeforeUpload(let m), .failedAfterUpload(let m, _):
            return m
        case .readyPreview, .idle:     return ""
        }
    }

    /// Starts the prepare → readyPreview chain. Caller is expected to show
    /// the preview composer once `state == .readyPreview`.
    func begin(_ source: PickerSource) {
        pickedSource = source
        workTask?.cancel()
        prepared?.remove()
        prepared = nil
        thumbnail = nil
        state = .preparing

        workTask = Task { [weak self] in
            await self?.prepareInternal(source)
        }
    }

    /// Called from the composer's send button. Triggers upload then send.
    func confirmSend(onSuccess: @escaping (Message) -> Void) {
        guard let prepared else { return }
        // If we already uploaded once, skip the prepare/upload step.
        if case .failedAfterUpload(_, let mediaId) = state {
            workTask = Task { [weak self] in
                await self?.sendMessage(mediaId: mediaId, prepared: prepared, onSuccess: onSuccess)
            }
            return
        }
        workTask = Task { [weak self] in
            await self?.uploadAndSend(prepared: prepared, onSuccess: onSuccess)
        }
    }

    /// Retry from the current failure point. Re-uses uploaded media when
    /// possible.
    func retry(onSuccess: @escaping (Message) -> Void) {
        switch state {
        case .failedBeforeUpload:
            // Re-prepare from the original picked source.
            guard let pickedSource else { return }
            begin(pickedSource)
        case .failedAfterUpload(_, let mediaId):
            guard let prepared else { return }
            workTask = Task { [weak self] in
                await self?.sendMessage(mediaId: mediaId, prepared: prepared, onSuccess: onSuccess)
            }
        default:
            break
        }
    }

    /// Cancels the in-flight task, removes any local file, returns to idle.
    /// The orphaned pending media row (if any) will be reaped by
    /// deleteExpiredMedia within 30 minutes.
    func cancel() {
        workTask?.cancel()
        workTask = nil
        prepared?.remove()
        prepared = nil
        thumbnail = nil
        uploadTicket = nil
        pickedSource = nil
        caption = ""
        state = .idle
    }

    func reset() { cancel() }

    // MARK: - Internals

    private func prepareInternal(_ source: PickerSource) async {
        do {
            switch source {
            case .imageData(let data, let mime):
                let file = try ImageCompressor.prepare(data: data, sourceMime: mime)
                prepared = file
                thumbnail = (try? Data(contentsOf: file.localURL))
                    .flatMap(UIImage.init(data:))
                state = .readyPreview
            case .videoFile(let url):
                let file = try await VideoCompressor.prepare(sourceURL: url)
                prepared = file
                thumbnail = await VideoCompressor.thumbnail(for: file.localURL)
                state = .readyPreview
            }
        } catch is CancellationError {
            // user-initiated cancel
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "media.error.compressionFailed")
            state = .failedBeforeUpload(message: message)
            GALog.media.error("prepare failed: \(error.localizedDescription)")
        }
    }

    private func uploadAndSend(prepared file: MediaPreparedFile,
                               onSuccess: @escaping (Message) -> Void) async {
        do {
            state = .uploading
            let ticket = try await MediaService.shared.requestUpload(roomId: roomId, file: file)
            uploadTicket = ticket
            try await MediaService.shared.upload(file: file, using: ticket)

            await sendMessage(mediaId: ticket.mediaId, prepared: file, onSuccess: onSuccess)
        } catch is CancellationError {
            // ignore — state already updated by cancel()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "media.error.uploadFailed")
            state = .failedBeforeUpload(message: message)
            GALog.media.error("upload failed: \(error.localizedDescription)")
        }
    }

    private func sendMessage(mediaId: UUID, prepared file: MediaPreparedFile,
                             onSuccess: @escaping (Message) -> Void) async {
        do {
            state = .sending
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = try await ChatService.shared.sendMediaMessage(
                roomId: roomId, mediaId: mediaId,
                caption: trimmed.isEmpty ? nil : trimmed
            )
            onSuccess(msg)
            file.remove()
            prepared = nil
            thumbnail = nil
            uploadTicket = nil
            pickedSource = nil
            caption = ""
            state = .idle
        } catch is CancellationError {
            // ignore
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "media.error.uploadFailed")
            state = .failedAfterUpload(message: message, mediaId: mediaId)
            GALog.media.error("send media message failed: \(error.localizedDescription)")
        }
    }
}
