import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    var isSending: Bool
    var canSend: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(GAColors.border).frame(height: 0.5)
            HStack(alignment: .bottom, spacing: GASpacing.sm) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("chat.input.placeholder")
                            .font(GATypography.body)
                            .foregroundStyle(GAColors.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $text, axis: .vertical)
                        .font(GATypography.body)
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($isFocused)
                        .textInputAutocapitalization(.sentences)
                }
                .background(GAColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GACornerRadius.large,
                                     style: .continuous)
                        .strokeBorder(GAColors.border, lineWidth: 1)
                )

                Button(action: { if canSend { onSend() } }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GAColors.accentText)
                        .frame(width: 38, height: 38)
                        .background(canSend ? GAColors.accent : GAColors.surfaceRaised)
                        .clipShape(Circle())
                        .opacity(isSending ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
                .accessibilityLabel(String(localized: "chat.input.send"))
            }
            .padding(.horizontal, GASpacing.lg)
            .padding(.vertical, GASpacing.sm)
            .background(GAColors.background)
        }
    }
}
