import SwiftUI

struct ChatMessageBubble: View {
    let message: Message
    let isMine: Bool
    /// `nil` for text messages.
    let mediaAsset: MediaAsset?
    /// Sender-only: their own local thumbnail, used to render a
    /// blurred-with-noise backdrop in the bubble. Always nil on the
    /// receiver side — receiver never sees image bytes pre-open.
    var localThumbnail: UIImage? = nil
    /// Tap on a viewable media bubble to open. Bubble suppresses the tap
    /// when not openable (sender's own bubble, already viewed, etc.).
    let onTapMedia: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: GASpacing.xxxl) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                bubbleBody
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(GATypography.caption)
                    .foregroundStyle(GAColors.textTertiary)
                    .padding(.horizontal, 4)
            }
            .frame(alignment: isMine ? .trailing : .leading)
            if !isMine { Spacer(minLength: GASpacing.xxxl) }
        }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        switch message.messageType {
        case .text, .system:
            textBubble
        case .image, .gif, .video:
            // Once view-once media has been consumed (viewed by the
            // receiver, expired, or storage cleaned up) the bubble
            // collapses to a small text-only "Expired photo/gif/video"
            // chip — no decorative chrome, no badges. Same shape on
            // both sides.
            if isExpiredMedia {
                expiredTextBubble
            } else {
                mediaBubble
            }
        }
    }

    private var textBubble: some View {
        Text(message.body ?? "")
            .font(GATypography.body)
            .foregroundStyle(textColor)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, GASpacing.md)
            .padding(.vertical, 10)
            .background(bubbleFill)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.large,
                                 style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.75)
            )
    }

    private var expiredTextBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.slash")
                .font(.system(size: 12, weight: .semibold))
            Text(expiredText)
                .font(GATypography.footnote)
        }
        .foregroundStyle(GAColors.textTertiary)
        .padding(.horizontal, GASpacing.md)
        .padding(.vertical, 8)
        .background(GAColors.surfaceRaised,
                    in: Capsule())
        .overlay(Capsule().strokeBorder(GAColors.border, lineWidth: 0.5))
    }

    private var expiredText: String {
        switch message.messageType {
        case .video: return String(localized: "media.expired.video")
        case .gif:   return String(localized: "media.expired.gif")
        default:     return String(localized: "media.expired.photo")
        }
    }

    /// True when there's no longer a viewable image — either because
    /// the receiver has opened it, the storage object was deleted, or
    /// the row TTL'd. Both sides converge to the expired text bubble.
    private var isExpiredMedia: Bool {
        guard let a = mediaAsset else { return false }
        if a.storageDeletedAt != nil { return true }
        if a.status == .viewed || a.status == .expired || a.status == .deleted {
            return true
        }
        if a.viewedAt != nil { return true }
        return false
    }

    // MARK: - Media bubble

    private var mediaBubble: some View {
        let view = mediaContent
            .frame(width: 220, height: 220)
            .background(bubbleFill)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.large,
                                 style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.75)
            )
            // View-once badge in the top-right of the bubble: eye icon
            // + "1" so the user understands the receiver gets one look
            // before the media disappears.
            .overlay(alignment: .topTrailing) {
                viewOnceBadge
                    .padding(8)
            }

        return Group {
            if isOpenable {
                Button(action: { onTapMedia?() }) { view }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewOnceLabel)
                    .accessibilityHint(String(localized: "media.openOnce"))
            } else {
                view
            }
        }
    }

    private var viewOnceBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .bold))
            Text("1")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(isMine
                         ? GAColors.accentText
                         : GAColors.textPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(isMine
                           ? Color.black.opacity(0.32)
                           : Color.black.opacity(0.18))
        )
        .accessibilityLabel(Text("media.viewOnce.badge"))
    }

    @ViewBuilder
    private var mediaContent: some View {
        ZStack {
            // Sender side: render a heavily blurred version of their
            // own thumbnail with a noise overlay so the bubble looks
            // like the actual media they sent — just unreadable
            // enough to feel "view-once". Receiver side never gets
            // image bytes, so it falls back to the obscured backdrop.
            if isMine, let thumb = localThumbnail {
                blurredThumbBackdrop(thumb)
            } else {
                obscuredBackdrop

                VStack(spacing: GASpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 56, height: 56)
                        Image(systemName: iconName)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(iconTint)
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(GAColors.accentText)
                                .padding(4)
                                .background(GAColors.accent, in: Circle())
                                .offset(x: 18, y: 18)
                        }
                    }

                    Text(viewOnceLabel)
                        .font(GATypography.bodyEmphasized)
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, GASpacing.sm)

                    Text(actionLabel)
                        .font(GATypography.caption)
                        .foregroundStyle(textColor.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(GASpacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Heavy blur + grain overlay on the sender's local thumbnail.
    /// `radius` is tuned so virtually no detail survives but the dominant
    /// hue does — the user gets a hint of what they sent without it
    /// being legible.
    private func blurredThumbBackdrop(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 32, opaque: true)
                .clipped()
            // Mild dim so the blurred image sits behind the badge
            // legibly on bright photos.
            Color.black.opacity(0.10)
            // Reuse the dotted noise pattern from obscuredBackdrop so
            // the visual language stays consistent with the receiver
            // side and "view-once" is unmistakable.
            Canvas { ctx, size in
                let dot = Color.white.opacity(0.10)
                let step: CGFloat = 14
                for x in stride(from: CGFloat(0), to: size.width, by: step) {
                    for y in stride(from: CGFloat(0), to: size.height, by: step) {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                            with: .color(dot)
                        )
                    }
                }
            }
            .drawingGroup()
        }
    }

    /// Soft obscured backdrop. Tinted by sender vs receiver but never
    /// reveals any actual media — the bytes never leave storage.
    private var obscuredBackdrop: some View {
        let base = isMine ? GAColors.accent : GAColors.surfaceRaised
        return ZStack {
            base
            LinearGradient(
                colors: [
                    Color.white.opacity(isMine ? 0.10 : 0.04),
                    Color.black.opacity(0.06),
                    Color.white.opacity(isMine ? 0.06 : 0.02),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft repeating dots → quiet, premium, "blurred" feel.
            // .drawingGroup rasterizes the canvas once instead of
            // re-running the for-loop on every body re-eval.
            Canvas { ctx, size in
                let dot = Color.white.opacity(isMine ? 0.06 : 0.04)
                let step: CGFloat = 14
                for x in stride(from: CGFloat(0), to: size.width, by: step) {
                    for y in stride(from: CGFloat(0), to: size.height, by: step) {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                            with: .color(dot)
                        )
                    }
                }
            }
            .drawingGroup()
        }
    }

    // MARK: - Helpers

    private var isOpenable: Bool {
        guard !isMine,
              let asset = mediaAsset,
              asset.viewOnce,
              asset.status == .active,
              asset.viewedAt == nil
        else { return false }
        return onTapMedia != nil
    }

    /// Show the small lock badge while the receiver hasn't opened yet,
    /// or for the sender's own bubble before the receiver opens.
    private var isLocked: Bool {
        guard let asset = mediaAsset else { return true }
        return asset.viewedAt == nil
            && asset.status != .viewed
            && asset.status != .deleted
            && asset.status != .expired
    }

    private var iconName: String {
        switch message.messageType {
        case .video: return "play.fill"
        case .gif:   return "sparkles"
        default:     return "eye"
        }
    }

    private var iconTint: Color {
        isMine ? GAColors.accentText : GAColors.accent
    }

    private var viewOnceLabel: String {
        switch message.messageType {
        case .video: return String(localized: "media.viewOnce.video")
        case .gif:   return String(localized: "media.viewOnce.gif")
        default:     return String(localized: "media.viewOnce.photo")
        }
    }

    private var actionLabel: String {
        if isMine {
            // Sender side
            if let a = mediaAsset,
               a.status == .expired || a.status == .deleted {
                return String(localized: "media.unavailable")
            }
            if let a = mediaAsset, a.viewedAt != nil || a.status == .viewed {
                return String(localized: "media.opened")
            }
            return String(localized: "media.viewOnce.label")
        } else {
            // Receiver side
            guard let a = mediaAsset else {
                return String(localized: "media.openOnce")
            }
            if a.status == .active && a.viewedAt == nil {
                return String(localized: "media.openOnce")
            }
            // Once the receiver has viewed and the storage object has been
            // deleted, the media is gone for good. Show unavailable.
            if a.storageDeletedAt != nil
                || a.status == .deleted
                || a.status == .expired {
                return String(localized: "media.unavailable")
            }
            if a.viewedAt != nil || a.status == .viewed {
                return String(localized: "media.viewed")
            }
            return String(localized: "media.unavailable")
        }
    }

    private var bubbleFill: Color {
        isMine ? GAColors.accent : GAColors.surface
    }

    private var textColor: Color {
        isMine ? GAColors.accentText : GAColors.textPrimary
    }

    private var borderColor: Color {
        isMine ? Color.clear : GAColors.border
    }
}
