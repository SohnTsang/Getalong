import SwiftUI

struct QuickStartProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm: QuickStartProfileViewModel

    init(userId: UUID) {
        _vm = StateObject(wrappedValue: QuickStartProfileViewModel(userId: userId))
    }

    var body: some View {
        GAScreen(maxWidth: 520) {
            VStack(alignment: .leading, spacing: GASpacing.xl) {

                header

                GACard(kind: .standard, padding: GASpacing.xl) {
                    VStack(spacing: GASpacing.lg) {
                        GATextField(title: "Handle",
                                    text: $vm.getalongId,
                                    placeholder: "your_handle",
                                    systemImage: "at",
                                    autocapitalization: .never,
                                    helperText: "Lowercase letters, numbers, underscores. 3–20 chars.",
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
                                    autocapitalization: .sentences,
                                    helperText: "This is the first thing people see.")
                    }
                }

                GACard {
                    VStack(alignment: .leading, spacing: GASpacing.lg) {
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

                GACard(kind: vm.is18Confirmed ? .highlight : .standard) {
                    Toggle(isOn: $vm.is18Confirmed) {
                        VStack(alignment: .leading, spacing: GASpacing.xs) {
                            Text("I confirm I am 18 or older.")
                                .font(GATypography.bodyEmphasized)
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

                Button { Task { await session.signOut() } } label: {
                    Text("Sign out")
                        .font(GATypography.footnote.weight(.medium))
                        .foregroundStyle(GAColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, GASpacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.lg) {
            Text("One sentence\nis enough.")
                .font(GATypography.editorial)
                .foregroundStyle(GAColors.textPrimary)
                .lineSpacing(-2)
                .kerning(-0.4)
            Text("Pick a handle, say something true, and you're in.\nYou can change all of this later.")
                .font(GATypography.body)
                .foregroundStyle(GAColors.textSecondary)
                .lineSpacing(2)
        }
    }

    // MARK: - Pickers

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
                Text(title.uppercased())
                    .font(GATypography.sectionTitle)
                    .tracking(0.6)
                    .foregroundStyle(GAColors.textTertiary)
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

    private func pickerTile(title: String,
                            isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GATypography.callout.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, GASpacing.md)
                .background(isSelected ? GAColors.accentSoft : GAColors.surfaceRaised)
                .foregroundStyle(isSelected ? GAColors.accent : GAColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                     style: .continuous)
                        .strokeBorder(isSelected ? GAColors.accent.opacity(0.6)
                                                 : GAColors.border,
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
