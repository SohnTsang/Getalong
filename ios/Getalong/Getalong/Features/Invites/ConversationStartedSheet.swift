import SwiftUI

/// Replaces the old "Chat created" alert. Shown right after a Live or
/// Missed signal is accepted; lets the user open the new conversation.
struct ConversationStartedSheet: View {
    let roomId: UUID
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var openChat: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                GAColors.background.ignoresSafeArea()

                VStack(spacing: GASpacing.lg) {
                    Spacer(minLength: 0)

                    ZStack {
                        Circle()
                            .fill(GAColors.accentSoft)
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(GAColors.accent)
                    }
                    .padding(.top, GASpacing.xxl)

                    VStack(spacing: GASpacing.xs) {
                        Text("chat.created.title")
                            .font(GATypography.title)
                            .foregroundStyle(GAColors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("chat.created.subtitle")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, GASpacing.lg)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: GASpacing.sm) {
                        GAButton(title: String(localized: "chat.created.open"),
                                 kind: .primary) {
                            openChat = true
                        }
                        GAButton(title: String(localized: "common.notNow"),
                                 kind: .ghost) {
                            onDismiss()
                            dismiss()
                        }
                    }
                    .padding(.horizontal, GASpacing.xl)
                    .padding(.bottom, GASpacing.xl)
                }
            }
            .navigationDestination(isPresented: $openChat) {
                ChatRoomView(roomId: roomId, partner: nil)
            }
        }
    }
}
