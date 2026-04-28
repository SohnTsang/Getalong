import Foundation
import AVFoundation
import UIKit

/// Compresses a source video file to MP4/H.264 around 720p, validating
/// duration against the server limit.
enum VideoCompressor {

    static func prepare(sourceURL: URL) async throws -> MediaPreparedFile {
        let asset = AVURLAsset(url: sourceURL)

        // Duration check.
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw MediaPreparationError.readFailed
        }
        let secs = CMTimeGetSeconds(duration)
        guard secs.isFinite, secs > 0 else { throw MediaPreparationError.readFailed }
        if secs > MediaPolicy.videoMaxDuration {
            throw MediaPreparationError.videoTooLong
        }

        // Quality ladder: try presets from highest to lowest until
        // one produces output within the byte cap. Most ordinary
        // phone footage encodes fine at 720p; high-motion clips (60fps
        // gaming, action) can overflow even at 720p — stepping down
        // to medium and then low quality keeps the send path from
        // hard-failing on those.
        let compatible = await AVAssetExportSession.compatiblePresets(asset: asset)
        let ladder = [
            AVAssetExportPreset1280x720,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality,
        ].filter { compatible.contains($0) }
        guard !ladder.isEmpty else {
            throw MediaPreparationError.compressionFailed
        }

        var outURL = MediaTempFile.make(extension: "mp4")
        var size: Int64 = 0
        var produced = false

        for (idx, preset) in ladder.enumerated() {
            try? FileManager.default.removeItem(at: outURL)
            outURL = MediaTempFile.make(extension: "mp4")

            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            session.outputURL = outURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true

            await session.export()
            if session.status != .completed { continue }

            let attrs = try? FileManager.default.attributesOfItem(atPath: outURL.path)
            size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            if size <= MediaPolicy.videoMaxBytes {
                produced = true
                break
            }
            // Else loop and try the next, lower-quality preset.
            // Don't bother retrying if there are no more rungs.
            if idx == ladder.count - 1 {
                try? FileManager.default.removeItem(at: outURL)
                throw MediaPreparationError.stillTooLargeAfterCompression
            }
        }

        guard produced else {
            try? FileManager.default.removeItem(at: outURL)
            throw MediaPreparationError.compressionFailed
        }

        // Pixel size is best-effort.
        let track = try? await asset.loadTracks(withMediaType: .video).first
        var w: Int?, h: Int?
        if let t = track, let size = try? await t.load(.naturalSize) {
            w = Int(abs(size.width))
            h = Int(abs(size.height))
        }

        // Tiny preview from the first frame so the chat bubble can
        // render the same blurred-noise backdrop on both sides.
        let previewImage = await Self.thumbnail(for: outURL, maxDimension: 24)
        let previewBase64: String? = previewImage
            .flatMap { $0.jpegData(compressionQuality: 0.4) }?
            .base64EncodedString()

        return MediaPreparedFile(
            localURL: outURL, mimeType: "video/mp4", kind: .video,
            sizeBytes: size, durationSeconds: Int(ceil(secs)),
            width: w, height: h,
            previewBase64: previewBase64
        )
    }

    /// Generates a small thumbnail for previewing in the composer.
    static func thumbnail(for url: URL,
                          maxDimension: CGFloat = 480) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        return await withCheckedContinuation { cont in
            gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                if let cg {
                    cont.resume(returning: UIImage(cgImage: cg))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

private extension AVAssetExportSession {
    /// Returns which of our three quality rungs are compatible with
    /// the asset, in descending quality order.
    static func compatiblePresets(asset: AVAsset) async -> [String] {
        async let ok720    = isCompatible(.preset1280x720, with: asset)
        async let okMedium = isCompatible(.mediumQuality,  with: asset)
        async let okLow    = isCompatible(.lowQuality,     with: asset)
        var out: [String] = []
        if await ok720    { out.append(AVAssetExportPreset1280x720) }
        if await okMedium { out.append(AVAssetExportPresetMediumQuality) }
        if await okLow    { out.append(AVAssetExportPresetLowQuality) }
        // Medium is virtually always compatible — guarantee at least
        // one rung so the caller never sees an empty ladder.
        if out.isEmpty { out.append(AVAssetExportPresetMediumQuality) }
        return out
    }

    enum NamedPreset {
        case preset1280x720, mediumQuality, lowQuality
        var rawValue: String {
            switch self {
            case .preset1280x720: return AVAssetExportPreset1280x720
            case .mediumQuality:  return AVAssetExportPresetMediumQuality
            case .lowQuality:     return AVAssetExportPresetLowQuality
            }
        }
    }

    private static func isCompatible(_ preset: NamedPreset, with asset: AVAsset) async -> Bool {
        await withCheckedContinuation { cont in
            AVAssetExportSession.determineCompatibility(
                ofExportPreset: preset.rawValue,
                with: asset, outputFileType: .mp4
            ) { ok in cont.resume(returning: ok) }
        }
    }
}
