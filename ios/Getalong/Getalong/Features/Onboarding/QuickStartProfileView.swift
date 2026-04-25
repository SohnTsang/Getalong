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
                    VStack(alignment: .leading, spacing: GASpacing.md) {
                        pickerSection(title: "I am",
                                      hint: "Optional",
                                      options: Gender.allCases,
                                      selection: $vm.gender,
                                      label: { $0.label })
                        pickerSection(title: "I want to see",
                                      hint: "Optional",
                                      options: InterestedInGender.allCases,
                                      selection: $vm.interestedIn,
                                      label: { $0.label })
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

    /// Optional segmented picker with a leading "Skip" tile.
    @ViewBuilder
    private func pickerSection<T: CaseIterable & Identifiable & Hashable>(
        title: String,
        hint: String?,
        options: T.AllCases,
        selection: Binding<T?>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            HStack {
                Text(title)
                    .font(GATypography.caption)
                    .foregroundStyle(GAColors.textSecondary)
                Spacer()
                if let hint {
                    Text(hint)
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textTertiary)
                }
            }
            HStack(spacing: GASpacing.sm) {
                pickerTile(title: "Skip",
                           isSelected: selection.wrappedValue == nil) {
                    selection.wrappedValue = nil
                }
                ForEach(Array(options)) { option in
                    pickerTile(title: label(option),
                               isSelected: selection.wrappedValue == option) {
                        selection.wrappedValue = option
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pickerTile(title: String,
                            isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GATypography.callout)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, GASpacing.md)
                .background(isSelected ? GAColors.accentSoft : GAColors.surfaceMuted)
                .foregroundStyle(isSelected ? GAColors.accent : GAColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.sm,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GACornerRadius.sm,
                                     style: .continuous)
                        .stroke(isSelected ? GAColors.accent : GAColors.border,
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QuickStartProfileView(userId: UUID())
        .environmentObject(SessionManager())
}
