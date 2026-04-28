import SwiftUI

/// Outgoing image bubble shown the instant the user taps Send in the
/// preview sheet — before the upload completes. It mirrors the look of
/// a real outgoing media bubble (`ChatMessageBubble`) so the chat feels
/// snappy: the bubble appears, then the spinner fades away when the
/// server confirms.
///
/// On failure it flips to a retry/remove chip pair below the image.
struct PendingOutgoingMediaBubble: View {
    let item: ChatRoomViewModel.PendingMediaItem
    let onRetry: () -> Void
    let onRemove: () -> Void

    private let imageWidth: CGFloat = 220
    private let imageHeight: CGFloat = 280

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: GASpacing.xxxl)
            VStack(alignment: .trailing, spacing: 6) {
                bubble
                if case .failed(let m) = item.state {
                    failureRow(m)
                }
            }
        }
    }

    private var bubble: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let img = item.thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageWidth, height: imageHeight)
                        .clipped()
                } else {
                    Color.black.opacity(0.06)
                        .frame(width: imageWidth, height: imageHeight)
                }
                stateOverlay
            }
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                        style: .continuous))

            viewOnceBadge
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch item.state {
        case .sending:
            ZStack {
                Color.black.opacity(0.18)
                ProgressView().tint(.white).controlSize(.small)
            }
        case .failed:
            ZStack {
                Color.black.opacity(0.32)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var viewOnceBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill").font(.system(size: 10, weight: .bold))
            Text("1").font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.32)))
        .accessibilityLabel(Text("media.viewOnce.badge"))
    }

    private func failureRow(_ message: String) -> some View {
        HStack(spacing: GASpacing.sm) {
            Text(message)
                .font(GATypography.caption)
                .foregroundStyle(GAColors.danger)
                .lineLimit(2)
            Button(String(localized: "media.retry"), action: onRetry)
                .font(GATypography.caption.weight(.semibold))
                .foregroundStyle(GAColors.accent)
            Button(String(localized: "media.remove"), action: onRemove)
                .font(GATypography.caption.weight(.semibold))
                .foregroundStyle(GAColors.textTertiary)
        }
    }
}
