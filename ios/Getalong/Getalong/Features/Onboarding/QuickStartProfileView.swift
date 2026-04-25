import SwiftUI

struct QuickStartProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm: QuickStartProfileViewModel

    init(userId: UUID) {
        _vm = StateObject(wrappedValue: QuickStartProfileViewModel(userId: userId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GASpacing.xl) {

                VStack(alignment: .leading, spacing: GASpacing.sm) {
                    Text("Say one thing about you")
                        .font(GATypography.display)
                        .foregroundStyle(GAColors.textPrimary)
                    Text("Getalong starts with words. You can edit this anytime.")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textSecondary)
                }

                GACard {
                    VStack(spacing: GASpacing.md) {
                        GATextField(title: "Handle",
                                    text: $vm.getalongId,
                                    placeholder: "your_handle",
                                    systemImage: "at",
                                    autocapitalization: .never,
                                    errorMessage: vm.handleHint)
                        GATextField(title: "Display name",
                                    text: $vm.displayName,
                                    placeholder: "What should we call you?",
                                    systemImage: "person",
                                    autocapitalization: .words)
                        GATextField(title: "One-line intro",
                                    text: $vm.oneLineIntro,
                                    placeholder: "Optional. Up to a sentence.",
                                    systemImage: "text.alignleft",
                                    autocapitalization: .sentences)
                    }
                }

                GACard {
                    Toggle(isOn: $vm.is18Confirmed) {
                        VStack(alignment: .leading, spacing: GASpacing.xs) {
                            Text("I confirm I am 18 or older.")
                                .font(GATypography.body)
                                .foregroundStyle(GAColors.textPrimary)
                            Text("Getalong is an 18+ app.")
                                .font(GATypography.footnote)
                                .foregroundStyle(GAColors.textSecondary)
                        }
                    }
                    .tint(GAColors.accent)
                }

                if let error = vm.errorMessage {
                    GAErrorBanner(message: error,
                                  onDismiss: { vm.errorMessage = nil })
                }

                GAButton(title: "Continue",
                         kind: .primary,
                         isLoading: vm.isWorking,
                         isDisabled: !vm.canSubmit) {
                    Task { await vm.submit(into: session) }
                }

                Button {
                    Task { await session.signOut() }
                } label: {
                    Text("Sign out")
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, GASpacing.sm)
            }
            .padding(.horizontal, GASpacing.lg)
            .padding(.vertical, GASpacing.xxl)
        }
        .background(GAColors.background.ignoresSafeArea())
    }
}

#Preview {
    QuickStartProfileView(userId: UUID())
        .environmentObject(SessionManager())
}
