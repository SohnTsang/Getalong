import SwiftUI

/// Temporary developer/test affordance to send a live invite by handle.
/// Will be removed once Discovery is built.
struct DevComposeInviteCard: View {
    @ObservedObject var vm: InvitesViewModel

    var body: some View {
        GACard {
            VStack(alignment: .leading, spacing: GASpacing.md) {
                HStack {
                    Label("Dev: send invite by handle",
                          systemImage: "wrench.and.screwdriver")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textSecondary)
                    Spacer()
                    Text("TEMP")
                        .font(GATypography.caption)
                        .padding(.horizontal, GASpacing.sm)
                        .padding(.vertical, 2)
                        .background(GAColors.warning.opacity(0.15))
                        .foregroundStyle(GAColors.warning)
                        .clipShape(Capsule())
                }

                GATextField(title: "Recipient handle",
                            text: $vm.composeHandle,
                            placeholder: "their_handle",
                            systemImage: "at",
                            autocapitalization: .never)

                GATextField(title: "Message (optional)",
                            text: $vm.composeMessage,
                            placeholder: "Up to a sentence",
                            systemImage: "text.alignleft",
                            autocapitalization: .sentences)

                if let err = vm.composeError {
                    GAErrorBanner(message: err,
                                  onDismiss: { vm.composeError = nil })
                }

                GAButton(title: "Send live invite",
                         kind: .primary,
                         size: .compact,
                         isLoading: vm.composeIsSending,
                         isDisabled: vm.composeIsSending) {
                    Task { await vm.sendDevCompose() }
                }
            }
        }
    }
}
