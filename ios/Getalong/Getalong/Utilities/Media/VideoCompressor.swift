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

        // Pick a compatible export preset. 1280x720 keeps file size in check
        // for 15-second clips. Fall back to medium if 720p isn't compatible
        // with this asset.
        let candidates = [AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality]
        let compatible = await AVAssetExportSession.compatiblePresets(asset: asset)
        let preset = candidates.first(where: { compatible.contains($0) })
            ?? AVAssetExportPresetMediumQuality

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw MediaPreparationError.compressionFailed
        }
        let outURL = MediaTempFile.make(extension: "mp4")
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        if session.status != .completed {
            try? FileManager.default.removeItem(at: outURL)
            throw MediaPreparationError.compressionFailed
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: outURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        if size > MediaPolicy.videoMaxBytes {
            try? FileManager.default.removeItem(at: outURL)
            throw MediaPreparationError.stillTooLargeAfterCompression
        }

        // Pixel size is best-effort.
        let track = try? await asset.loadTracks(withMediaType: .video).first
        var w: Int?, h: Int?
        if let t = track, let size = try? await t.load(.naturalSize) {
            w = Int(abs(size.width))
            h = Int(abs(size.height))
        }

        return MediaPreparedFile(
            localURL: outURL, mimeType: "video/mp4", kind: .video,
            sizeBytes: size, durationSeconds: Int(ceil(secs)),
            width: w, height: h
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
    static func compatiblePresets(asset: AVAsset) async -> [String] {
        await withCheckedContinuation { cont in
            AVAssetExportSession.determineCompatibility(
                ofExportPreset: AVAssetExportPreset1280x720,
                with: asset, outputFileType: .mp4
            ) { ok720 in
                if ok720 { cont.resume(returning: [AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality]) }
                else { cont.resume(returning: [AVAssetExportPresetMediumQuality]) }
            }
        }
    }
}
