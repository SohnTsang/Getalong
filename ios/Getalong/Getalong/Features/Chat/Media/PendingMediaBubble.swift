import SwiftUI

/// The local bubble shown on the sender's side while a piece of media is
/// being prepared, uploaded, or sent — and after a failure for retry/remove.
struct PendingMediaBubble: View {
    @ObservedObject var controller: MediaUploadController
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: GASpacing.xxxl)
            VStack(alignment: .trailing, spacing: 4) {
                bubble
                if let action = trailingActionLabel {
                    Text(action)
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textTertiary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var bubble: some View {
        VStack(spacing: GASpacing.sm) {
            ZStack {
                if let img = controller.thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 160)
                        .clipped()
                } else {
                    Color.black.opacity(0.06)
                        .frame(width: 220, height: 160)
                }
                stateOverlay
            }
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                        style: .continuous))

            HStack(spacing: GASpacing.sm) {
                if isFailed {
                    Button(action: { controller.retry(onSuccess: { _ in }) }) {
                        Label(String(localized: "media.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive, action: onRemove) {
                        Text("media.remove")
                    }
                    .buttonStyle(.bordered)
                } else if isInFlight {
                    Button(action: onRemove) {
                        Label(String(localized: "media.cancelUpload"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(GASpacing.sm)
        .background(GAColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.large,
                             style: .continuous)
                .strokeBorder(GAColors.border, lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch controller.state {
        case .preparing, .uploading, .sending:
            ZStack {
                Color.black.opacity(0.25)
                VStack(spacing: GASpacing.sm) {
                    ProgressView().tint(.white)
                    Text(controller.stateLabel)
                        .font(GATypography.caption)
                        .foregroundStyle(.white)
                }
            }
        case .failedBeforeUpload, .failedAfterUpload:
            ZStack {
                Color.black.opacity(0.25)
                VStack(spacing: GASpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text(controller.stateLabel)
                        .font(GATypography.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, GASpacing.sm)
                }
            }
        default:
            EmptyView()
        }
    }

    private var trailingActionLabel: String? {
        switch controller.state {
        case .preparing:  return String(localized: "media.preparing")
        case .uploading:  return String(localized: "media.uploading")
        case .sending:    return String(localized: "media.sending")
        case .failedBeforeUpload: return String(localized: "media.uploadFailed")
        case .failedAfterUpload:  return String(localized: "media.uploadFailed")
        default: return nil
        }
    }

    private var isFailed: Bool {
        switch controller.state {
        case .failedBeforeUpload, .failedAfterUpload: return true
        default: return false
        }
    }

    private var isInFlight: Bool {
        switch controller.state {
        case .preparing, .uploading, .sending: return true
        default: return false
        }
    }
}
