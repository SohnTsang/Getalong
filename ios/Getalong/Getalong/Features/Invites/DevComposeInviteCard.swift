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
                        GAStatusPill(label: String(localized: "signals.dev.title"),
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
                    Text("signals.dev.description")
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GATextField(title: String(localized: "signals.dev.recipient.label"),
                                text: $vm.composeHandle,
                                placeholder: "your_handle",
                                systemImage: "at",
                                autocapitalization: .never)

                    if let err = vm.composeError {
                        GAErrorBanner(message: err,
                                      onDismiss: { vm.composeError = nil })
                    }

                    GAButton(title: String(localized: "signals.send"),
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
