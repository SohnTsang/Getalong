import SwiftUI

struct ChatMessageBubble: View {
    let message: Message
    let isMine: Bool
    /// `nil` for text messages.
    let mediaAsset: MediaAsset?
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
            mediaBubble
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

    @ViewBuilder
    private var mediaContent: some View {
        VStack(spacing: GASpacing.sm) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(iconTint)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let a = mediaAsset, a.viewedAt != nil || a.status == .viewed {
                return String(localized: "media.opened")
            }
            if let a = mediaAsset,
               a.status == .expired || a.status == .deleted {
                return String(localized: "media.unavailable")
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
