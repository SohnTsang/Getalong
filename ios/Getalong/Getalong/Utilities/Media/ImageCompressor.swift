import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Compresses an image into JPEG (or keeps PNG for small alpha images, or
/// keeps GIF as-is for animated GIFs) while staying within the server's
/// per-kind byte limit.
enum ImageCompressor {

    /// Maximum dimension on the long edge after resizing.
    private static let maxLongEdge: CGFloat = 2048
    private static let initialJpegQuality: CGFloat = 0.82
    private static let minJpegQuality: CGFloat     = 0.55

    /// Detects whether the bytes represent an animated GIF.
    static func isAnimatedGIF(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        let type = CGImageSourceGetType(src) as String? ?? ""
        return type == (UTType.gif.identifier) && CGImageSourceGetCount(src) > 1
    }

    /// Detects whether PNG bytes carry meaningful transparency (cheap heuristic:
    /// we trust the source format and ImageIO).
    static func pngHasAlpha(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return false
        }
        let info = cg.alphaInfo
        return info == .first || info == .last
            || info == .premultipliedFirst || info == .premultipliedLast
    }

    /// Prepare bytes from a Photos picker / file. Picks JPEG, PNG, or GIF
    /// output based on the source.
    static func prepare(data: Data, sourceMime: String?) throws -> MediaPreparedFile {
        // Animated GIFs: keep as-is.
        if isAnimatedGIF(data) {
            let bytes = Int64(data.count)
            if bytes > MediaPolicy.gifMaxBytes {
                throw MediaPreparationError.fileTooLarge
            }
            let url = MediaTempFile.make(extension: "gif")
            try data.write(to: url)
            let (w, h) = pixelSize(data) ?? (0, 0)
            return MediaPreparedFile(
                localURL: url, mimeType: "image/gif", kind: .gif,
                sizeBytes: bytes, durationSeconds: nil,
                width: w == 0 ? nil : w, height: h == 0 ? nil : h
            )
        }

        // Decode to UIImage with correct orientation.
        guard let raw = UIImage(data: data) else {
            throw MediaPreparationError.readFailed
        }
        let normalized = raw.normalizedOrientation()
        let resized = normalized.resizedToFit(maxLongEdge: maxLongEdge)

        // Small PNG with alpha → keep PNG.
        if sourceMime == "image/png", pngHasAlpha(data) {
            if let png = resized.pngData(), Int64(png.count) <= MediaPolicy.imageMaxBytes {
                let url = MediaTempFile.make(extension: "png")
                try png.write(to: url)
                return MediaPreparedFile(
                    localURL: url, mimeType: "image/png", kind: .image,
                    sizeBytes: Int64(png.count), durationSeconds: nil,
                    width: Int(resized.size.width), height: Int(resized.size.height)
                )
            }
            // else fall through to JPEG.
        }

        // JPEG with quality stepping.
        var quality = initialJpegQuality
        var jpeg: Data? = resized.jpegData(compressionQuality: quality)
        while let d = jpeg, Int64(d.count) > MediaPolicy.imageMaxBytes,
              quality > minJpegQuality {
            quality -= 0.07
            jpeg = resized.jpegData(compressionQuality: quality)
        }
        guard let out = jpeg else {
            throw MediaPreparationError.compressionFailed
        }
        if Int64(out.count) > MediaPolicy.imageMaxBytes {
            throw MediaPreparationError.stillTooLargeAfterCompression
        }
        let url = MediaTempFile.make(extension: "jpg")
        try out.write(to: url)
        return MediaPreparedFile(
            localURL: url, mimeType: "image/jpeg", kind: .image,
            sizeBytes: Int64(out.count), durationSeconds: nil,
            width: Int(resized.size.width), height: Int(resized.size.height)
        )
    }

    private static func pixelSize(_ data: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resizedToFit(maxLongEdge: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return self }
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: floor(size.width * scale),
                             height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
