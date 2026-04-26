import Foundation
import PhotosUI
import UniformTypeIdentifiers
import SwiftUI

/// Bridges a `PhotosPickerItem` to one of the two `MediaUploadController`
/// picker sources (image data or video file URL).
enum MediaPickerLoader {
    static func resolve(_ item: PhotosPickerItem) async -> MediaUploadController.PickerSource? {
        // Try video first (heaviest), then image. Photos uses
        // movie/quicktime UTIs for videos.
        if let supports = try? await item.loadTransferable(type: VideoTransferable.self) {
            return .videoFile(supports.url)
        }
        if let data = try? await item.loadTransferable(type: Data.self) {
            let mime = inferImageMime(from: item) ?? "image/jpeg"
            return .imageData(data, sourceMime: mime)
        }
        return nil
    }

    private static func inferImageMime(from item: PhotosPickerItem) -> String? {
        // PhotosPickerItem.supportedContentTypes[0].preferredMIMEType is the
        // most reliable hint when available. Fall back to JPEG.
        let types = item.supportedContentTypes
        for t in types {
            if let mime = t.preferredMIMEType {
                if mime.hasPrefix("image/") { return mime }
            }
        }
        return nil
    }
}

/// Transferable that resolves a PhotosPicker video to a temporary file URL.
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { transferable in
            SentTransferredFile(transferable.url)
        } importing: { received in
            // Copy out of the system-managed inbox so we can keep the URL.
            let dest = MediaTempFile.make(extension: received.file.pathExtension.isEmpty
                                          ? "mov" : received.file.pathExtension)
            // Remove any leftover from a previous attempt at this name.
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}
