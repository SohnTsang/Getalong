import SwiftUI

struct ChatMessageBubble: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: GASpacing.xxxl) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
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
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(GATypography.caption)
                    .foregroundStyle(GAColors.textTertiary)
                    .padding(.horizontal, 4)
            }
            .frame(alignment: isMine ? .trailing : .leading)
            if !isMine { Spacer(minLength: GASpacing.xxxl) }
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
