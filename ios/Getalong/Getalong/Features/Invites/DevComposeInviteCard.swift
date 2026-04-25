import SwiftUI

/// Temporary developer/test affordance to send a live invite by handle.
/// Visually subordinate to the rest of the screen.
struct DevComposeInviteCard: View {
    @ObservedObject var vm: InvitesViewModel
    @State private var isExpanded: Bool = false

    var body: some View {
        GACard(kind: .standard, padding: GASpacing.lg) {
            VStack(alignment: .leading, spacing: GASpacing.md) {

                Button { withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() } } label: {
                    HStack {
                        GAStatusPill(label: "Developer test",
                                     systemImage: "wrench.and.screwdriver.fill",
                                     tint: GAColors.warning)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(GATypography.caption)
                            .foregroundStyle(GAColors.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text("Send a live invite by handle. This shortcut goes away once Discovery is built.")
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textSecondary)

                    GATextField(title: "Recipient handle",
                                text: $vm.composeHandle,
                                placeholder: "their_handle",
                                systemImage: "at",
                                autocapitalization: .never)

                    GATextField(title: "Message",
                                text: $vm.composeMessage,
                                placeholder: "Optional. Up to a sentence.",
                                systemImage: "text.alignleft",
                                autocapitalization: .sentences)

                    if let err = vm.composeError {
                        GAErrorBanner(message: err,
                                      onDismiss: { vm.composeError = nil })
                    }

                    GAButton(title: "Send live invite",
                             kind: .secondary,
                             size: .compact,
                             isLoading: vm.composeIsSending,
                             isDisabled: vm.composeIsSending) {
                        Task { await vm.sendDevCompose() }
                    }
                }
            }
        }
        .opacity(0.95)
    }
}
