import SwiftUI

/// Full-screen preview shown after the user picks an image (or video).
/// Letterboxed media on a near-black background, a small close button
/// top-left, a tiny view-once badge top-right, and a bold Send button
/// bottom-right. Tapping Send fires upload + send through the
/// `MediaUploadController`'s `confirmSend` path.
struct MediaPreviewSheet: View {
    @ObservedObject var controller: MediaUploadController
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            preview

            // Top-left close button. The view-once badge is now
            // overlaid on the image itself (inside `preview`) so it
            // visually belongs to the media, not the chrome.
            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                .padding(.horizontal, GASpacing.lg)
                .padding(.top, GASpacing.sm)
                Spacer()
            }

            // Bottom — error banner + Send.
            VStack {
                Spacer()
                if case .failedBeforeUpload(let m) = controller.state {
                    errorRow(m)
                } else if case .failedAfterUpload(let m, _) = controller.state {
                    errorRow(m)
                }
                HStack {
                    Spacer()
                    sendButton
                }
                .padding(.horizontal, GASpacing.lg)
                .padding(.bottom, GASpacing.lg)
            }
        }
        // Drag-down dismiss is what users expect from a preview pane —
        // we only block it while preparing/uploading/sending so a
        // half-finished send doesn't get orphaned.
        .interactiveDismissDisabled(isBusy)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let img = controller.thumbnail {
            // Overlay the view-once badge on the *image's* visible
            // rect (top-right) rather than the screen's top bar — the
            // badge belongs to the media. The overlay clips with the
            // image because it shares the same frame.
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .overlay(alignment: .topTrailing) {
                    viewOnceBadge
                        .padding(.top, GASpacing.sm)
                        .padding(.trailing, GASpacing.sm)
                }
                .padding(.vertical, GASpacing.xxl)
        } else {
            VStack(spacing: GASpacing.md) {
                ProgressView().controlSize(.large).tint(.white)
                Text("media.preparing")
                    .font(GATypography.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Buttons / chrome

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.cancel"))
        .disabled(isBusy)
        .opacity(isBusy ? 0.4 : 1)
    }

    private var viewOnceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 11, weight: .bold))
            Text("1")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .accessibilityLabel(Text("media.viewOnce.badge"))
    }

    private var sendButton: some View {
        Button {
            switch controller.state {
            case .readyPreview:
                onConfirm()
            case .failedBeforeUpload, .failedAfterUpload:
                controller.retry { _ in }
                onConfirm()
            default:
                break
            }
        } label: {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(GAColors.accentText)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(buttonTitle)
                    .font(GATypography.bodyEmphasized)
            }
            .foregroundStyle(GAColors.accentText)
            .padding(.horizontal, GASpacing.lg)
            .padding(.vertical, 12)
            .background(GAColors.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.55)
        .accessibilityLabel(String(localized: "common.send"))
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: GASpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(GATypography.footnote)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
        }
        .padding(GASpacing.md)
        .background(GAColors.danger.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                         style: .continuous))
        .padding(.horizontal, GASpacing.lg)
        .padding(.bottom, GASpacing.sm)
    }

    // MARK: - State helpers

    private var canSend: Bool {
        switch controller.state {
        case .readyPreview, .failedBeforeUpload, .failedAfterUpload: return true
        default: return false
        }
    }

    private var isBusy: Bool {
        switch controller.state {
        case .preparing, .uploading, .sending: return true
        default: return false
        }
    }

    private var buttonTitle: String {
        switch controller.state {
        case .uploading:                        return String(localized: "media.uploading")
        case .sending:                          return String(localized: "media.sending")
        case .preparing:                        return String(localized: "media.preparing")
        case .failedBeforeUpload, .failedAfterUpload:
            return String(localized: "media.retry")
        default:                                return String(localized: "common.send")
        }
    }
}
