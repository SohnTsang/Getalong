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
                        GATextField(title: String(localized: "quickstart.handle.label"),
                                    text: $vm.getalongId,
                                    placeholder: String(localized: "quickstart.handle.placeholder"),
                                    systemImage: "at",
                                    autocapitalization: .never,
                                    helperText: String(localized: "quickstart.handle.helper"),
                                    errorMessage: vm.handleHint)
                        GATextField(title: String(localized: "quickstart.displayName.label"),
                                    text: $vm.displayName,
                                    placeholder: String(localized: "quickstart.displayName.placeholder"),
                                    systemImage: "person",
                                    autocapitalization: .words)
                        GATextField(title: String(localized: "quickstart.signal.label"),
                                    text: $vm.oneLineIntro,
                                    placeholder: String(localized: "quickstart.signal.placeholder"),
                                    systemImage: "text.alignleft",
                                    autocapitalization: .sentences,
                                    helperText: String(localized: "quickstart.signal.helper"))
                    }
                }

                GACard {
                    VStack(alignment: .leading, spacing: GASpacing.lg) {
                        pickerSection(title: String(localized: "quickstart.gender.iAm"),
                                      hint: String(localized: "quickstart.optional"),
                                      options: Gender.allCases,
                                      selection: $vm.gender,
                                      label: { $0.localizedLabel })
                        pickerSection(title: String(localized: "quickstart.gender.wantToSee"),
                                      hint: String(localized: "quickstart.optional"),
                                      options: InterestedInGender.allCases,
                                      selection: $vm.interestedIn,
                                      label: { $0.localizedLabel })
                    }
                }

                GACard(kind: vm.is18Confirmed ? .highlight : .standard) {
                    Toggle(isOn: $vm.is18Confirmed) {
                        VStack(alignment: .leading, spacing: GASpacing.xs) {
                            Text("quickstart.age.confirmation")
                                .font(GATypography.bodyEmphasized)
                                .foregroundStyle(GAColors.textPrimary)
                            Text("quickstart.age.subtitle")
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

                GAButton(title: String(localized: "quickstart.continue"),
                         kind: .primary,
                         isLoading: vm.isWorking,
                         isDisabled: !vm.canSubmit) {
                    Task { await vm.submit(into: session) }
                }

                Button { Task { await session.signOut() } } label: {
                    Text("quickstart.signOut")
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
            VStack(alignment: .leading, spacing: 0) {
                Text("quickstart.title.line1")
                    .font(GATypography.editorial)
                    .foregroundStyle(GAColors.textPrimary)
                    .lineSpacing(-2)
                    .kerning(-0.4)
                Text("quickstart.title.line2")
                    .font(GATypography.editorial)
                    .foregroundStyle(GAColors.accent)
                    .lineSpacing(-2)
                    .kerning(-0.4)
            }
            Text("quickstart.subtitle")
                .font(GATypography.body)
                .foregroundStyle(GAColors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
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
                pickerTile(title: String(localized: "quickstart.gender.skip"),
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
