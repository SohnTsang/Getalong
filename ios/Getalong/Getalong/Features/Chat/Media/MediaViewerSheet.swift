import SwiftUI
import AVKit

/// Full-screen sheet that opens a one-time-view media. Calls
/// `openViewOnceMedia` when it appears, which atomically marks the media
/// as viewed before returning a short-lived signed URL. Closing the sheet
/// does not "uncook" the view-once status.
struct MediaViewerSheet: View {
    let mediaId: UUID
    let messageType: MessageType
    /// Called once we know the media has been marked viewed (success or
    /// "already viewed" — both transition the bubble to the "viewed" state).
    let onViewed: () -> Void
    let onClose: () -> Void

    @State private var state: ViewerState = .opening

    enum ViewerState {
        case opening
        case ready(url: URL, mime: String)
        case unavailable
        case error(message: String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch state {
            case .opening:
                VStack(spacing: GASpacing.md) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text("media.opening")
                        .font(GATypography.body)
                        .foregroundStyle(.white)
                }
            case .ready(let url, let mime):
                viewer(for: url, mime: mime)
            case .unavailable:
                placeholder(systemImage: "eye.slash",
                            text: String(localized: "media.unavailable"))
            case .error(let message):
                placeholder(systemImage: "exclamationmark.triangle",
                            text: message)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(GASpacing.lg)
                }
                Spacer()
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func viewer(for url: URL, mime: String) -> some View {
        if mime.hasPrefix("video/") {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
                .onAppear {
                    // Auto-play happens when AVPlayer is shown; nothing else
                    // to do here.
                }
        } else if mime == "image/gif" {
            // SwiftUI's Image doesn't animate GIFs; use a UIView wrapper.
            AnimatedGIFView(url: url)
                .ignoresSafeArea()
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().tint(.white)
                case .success(let image):
                    image.resizable().scaledToFit().padding()
                case .failure:
                    placeholder(systemImage: "exclamationmark.triangle",
                                text: String(localized: "media.error.openFailed"))
                @unknown default:
                    EmptyView()
                }
            }
            .ignoresSafeArea()
        }
    }

    private func placeholder(systemImage: String, text: String) -> some View {
        VStack(spacing: GASpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
            Text(text)
                .font(GATypography.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, GASpacing.xl)
        }
    }

    private func load() async {
        do {
            let resp = try await MediaService.shared.openViewOnce(mediaId: mediaId)
            // Notify caller so they can flip the bubble to "viewed" before
            // the user closes the sheet — we don't want a brief reopen path.
            onViewed()
            state = .ready(url: resp.signedUrl, mime: resp.mimeType)
        } catch let e as MediaServiceError {
            switch e {
            case .mediaAlreadyViewed, .mediaNotActive, .mediaExpired, .mediaNotFound:
                onViewed()
                state = .unavailable
            default:
                state = .error(message: e.errorDescription ?? String(localized: "media.error.openFailed"))
            }
        } catch {
            state = .error(message: String(localized: "media.error.openFailed"))
        }
    }
}

// MARK: - GIF view

import UIKit
import ImageIO

/// Tiny UIView wrapper that decodes the GIF frame stack and animates it.
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        Task {
            guard let data = try? Data(contentsOf: url),
                  let src = CGImageSourceCreateWithData(data as CFData, nil) else {
                return
            }
            let count = CGImageSourceGetCount(src)
            guard count > 1 else {
                if let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                    await MainActor.run { uiView.image = UIImage(cgImage: cg) }
                }
                return
            }
            var images: [UIImage] = []
            var totalDuration: TimeInterval = 0
            for i in 0..<count {
                if let cg = CGImageSourceCreateImageAtIndex(src, i, nil) {
                    images.append(UIImage(cgImage: cg))
                }
                totalDuration += GIFFrameDuration(at: i, source: src)
            }
            await MainActor.run {
                uiView.animationImages = images
                uiView.animationDuration = totalDuration > 0 ? totalDuration : Double(count) / 24.0
                uiView.animationRepeatCount = 0
                uiView.startAnimating()
            }
        }
    }

    private func GIFFrameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.05 }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval,
           unclamped > 0 { return unclamped }
        if let delay = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval,
           delay > 0 { return delay }
        return 0.05
    }
}
