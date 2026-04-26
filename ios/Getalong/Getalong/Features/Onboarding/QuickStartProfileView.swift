import SwiftUI

struct QuickStartProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm: QuickStartProfileViewModel

    init(userId: UUID) {
        _vm = StateObject(wrappedValue: QuickStartProfileViewModel(userId: userId))
    }

    var body: some View {
        GAScreen(maxWidth: 520, centerVertically: true) {
            VStack(alignment: .leading, spacing: GASpacing.xl) {

                header

                GACard(kind: .standard, padding: GASpacing.xl) {
                    VStack(spacing: GASpacing.lg) {
                        GATextField(title: String(localized: "quickstart.signal.label"),
                                    text: $vm.oneLineIntro,
                                    placeholder: String(localized: "quickstart.signal.placeholder"),
                                    autocapitalization: .sentences,
                                    helperText: String(localized: "quickstart.signal.helper"),
                                    errorMessage: vm.signalHint)
                    }
                }

                GACard {
                    VStack(alignment: .leading, spacing: GASpacing.lg) {
                        pickerSection(title: String(localized: "quickstart.gender.iAm"),
                                      options: Gender.allCases,
                                      selection: $vm.gender,
                                      label: { $0.localizedLabel })
                        pickerSection(title: String(localized: "quickstart.gender.wantToSee"),
                                      options: InterestedInGender.allCases,
                                      selection: $vm.interestedIn,
                                      label: { $0.localizedLabel })
                    }
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
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text("quickstart.title.line1")
                    .font(GATypography.heroSerif)
                    .foregroundStyle(GAColors.textPrimary)
                    .lineSpacing(-2)
                    .kerning(-0.3)
                Text("quickstart.title.line2")
                    .font(GATypography.heroSerif)
                    .foregroundStyle(GAColors.accent)
                    .lineSpacing(-2)
                    .kerning(-0.3)
            }
            Text("quickstart.subtitle")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pickers

    /// A wrapping picker — chips flow to a second row when there are too
    /// many to fit. No "Skip" option: the user must choose.
    @ViewBuilder
    private func pickerSection<T: CaseIterable & Identifiable & Hashable>(
        title: String,
        options: T.AllCases,
        selection: Binding<T?>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text(title.uppercased())
                .font(GATypography.sectionTitle)
                .tracking(0.6)
                .foregroundStyle(GAColors.textTertiary)
            FlowLayout(spacing: GASpacing.sm) {
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, GASpacing.lg)
                .padding(.vertical, 10)
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
