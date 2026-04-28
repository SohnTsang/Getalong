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
        // Outer row anchors the bubble to the correct side. The time
        // chip lives *inside* the bubble (bottom-right), like
        // WhatsApp/Telegram, so we don't render a separate trailing
        // timestamp here.
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: GASpacing.xxxl) }
            bubbleBody
            if !isMine { Spacer(minLength: GASpacing.xxxl) }
        }
    }

    private var formattedTime: String {
        message.createdAt.formatted(date: .omitted, time: .shortened)
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
        // Time floats at the bottom-right inside the bubble. We add
        // trailing+bottom padding to the body text so the timestamp
        // never overlaps the last line. Tail-side padding is widened
        // by `tailWidth` so the body stays clear of the speech tail.
        let tailW: CGFloat = ChatBubbleShape.tailWidth

        return Text(message.body ?? "")
            .font(GATypography.body)
            .foregroundStyle(textColor)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .padding(.leading, isMine ? 12 : 12 + tailW)
            .padding(.trailing, 64 + (isMine ? tailW : 0))
            .overlay(alignment: .bottomTrailing) {
                Text(formattedTime)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(timeColor)
                    .padding(.bottom, 4)
                    .padding(.trailing, 10 + (isMine ? tailW : 0))
            }
            .background(ChatBubbleShape(isMine: isMine).fill(bubbleFill))
            .overlay(
                ChatBubbleShape(isMine: isMine)
                    .stroke(borderColor, lineWidth: 0.75)
            )
    }

    private var timeColor: Color {
        // On the accent-filled outgoing bubble we need a light
        // translucent white. On the receiver bubble (surface fill)
        // tertiary text reads correctly already.
        isMine
            ? GAColors.accentText.opacity(0.75)
            : GAColors.textTertiary
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
        let tailW = ChatBubbleShape.tailWidth
        let view = mediaContent
            .frame(width: 220, height: 220)
            // Reserve `tailWidth` on the tail side so the shape's tail
            // sits in unused padding — the media content stays a full
            // 220×220 inside the bubble's body portion.
            .padding(.trailing, isMine ? tailW : 0)
            .padding(.leading,  isMine ? 0 : tailW)
            .background(ChatBubbleShape(isMine: isMine).fill(bubbleFill))
            .clipShape(ChatBubbleShape(isMine: isMine))
            .overlay(
                ChatBubbleShape(isMine: isMine)
                    .stroke(borderColor, lineWidth: 0.75)
            )
            // View-once badge in the top-right of the bubble body
            // (offset inward past the tail on the sender side).
            .overlay(alignment: .topTrailing) {
                viewOnceBadge
                    .padding(.top, 8)
                    .padding(.trailing, 8 + (isMine ? tailW : 0))
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

// MARK: - Bubble shape with speech tail

/// Rounded-rect chat bubble with a small speech tail at the bottom-
/// trailing corner. Mine -> tail at bottom-right; theirs -> bottom-left.
/// The tail is drawn entirely inside `rect`, so callers must reserve
/// `tailWidth` of horizontal padding on the tail side via the body
/// content insets.
struct ChatBubbleShape: Shape {
    let isMine: Bool
    static let tailWidth: CGFloat = 6
    private let radius: CGFloat = 18
    private let tailHeight: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = radius
        let tw = Self.tailWidth
        let th = tailHeight
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        if isMine {
            // Body occupies left portion; tail extends to maxX.
            let bodyMaxX = maxX - tw

            // top-left corner
            p.move(to: CGPoint(x: minX, y: minY + r))
            p.addArc(center: CGPoint(x: minX + r, y: minY + r),
                     radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(270),
                     clockwise: false)
            // top edge to top-right corner
            p.addLine(to: CGPoint(x: bodyMaxX - r, y: minY))
            p.addArc(center: CGPoint(x: bodyMaxX - r, y: minY + r),
                     radius: r,
                     startAngle: .degrees(270), endAngle: .degrees(0),
                     clockwise: false)
            // right edge down to where the tail begins
            p.addLine(to: CGPoint(x: bodyMaxX, y: maxY - th))
            // tail: curve out to the tip then back to body bottom edge
            p.addQuadCurve(
                to: CGPoint(x: maxX, y: maxY),
                control: CGPoint(x: bodyMaxX, y: maxY - th * 0.35)
            )
            p.addQuadCurve(
                to: CGPoint(x: bodyMaxX - r, y: maxY),
                control: CGPoint(x: bodyMaxX - r * 0.6, y: maxY)
            )
            // bottom edge back to bottom-left corner
            p.addLine(to: CGPoint(x: minX + r, y: maxY))
            p.addArc(center: CGPoint(x: minX + r, y: maxY - r),
                     radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(180),
                     clockwise: false)
            p.closeSubpath()
        } else {
            // Body occupies right portion; tail extends to minX.
            let bodyMinX = minX + tw

            // top-right corner
            p.move(to: CGPoint(x: maxX, y: minY + r))
            p.addArc(center: CGPoint(x: maxX - r, y: minY + r),
                     radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(-90),
                     clockwise: true)
            // top edge to top-left corner
            p.addLine(to: CGPoint(x: bodyMinX + r, y: minY))
            p.addArc(center: CGPoint(x: bodyMinX + r, y: minY + r),
                     radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(180),
                     clockwise: true)
            // left edge down to tail start
            p.addLine(to: CGPoint(x: bodyMinX, y: maxY - th))
            // tail: curve out left-and-down then back
            p.addQuadCurve(
                to: CGPoint(x: minX, y: maxY),
                control: CGPoint(x: bodyMinX, y: maxY - th * 0.35)
            )
            p.addQuadCurve(
                to: CGPoint(x: bodyMinX + r, y: maxY),
                control: CGPoint(x: bodyMinX + r * 0.6, y: maxY)
            )
            // bottom edge to bottom-right corner
            p.addLine(to: CGPoint(x: maxX - r, y: maxY))
            p.addArc(center: CGPoint(x: maxX - r, y: maxY - r),
                     radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(0),
                     clockwise: true)
            p.closeSubpath()
        }
        return p
    }
}
