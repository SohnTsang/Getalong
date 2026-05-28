import SwiftUI

struct QuickStartProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm: QuickStartProfileViewModel

    init(userId: UUID) {
        _vm = StateObject(wrappedValue: QuickStartProfileViewModel(userId: userId))
    }

    var body: some View {
        GAScreen(maxWidth: 520, centerVertically: false) {
            VStack(alignment: .leading, spacing: GASpacing.xl) {

                header

                // One honest line — the hero identity input.
                GACard(kind: .standard, padding: GASpacing.xl) {
                    VStack(alignment: .leading, spacing: GASpacing.md) {
                        GATextField(title: String(localized: "quickstart.signal.taipei.label"),
                                    text: $vm.oneLineIntro,
                                    placeholder: String(localized: "quickstart.signal.placeholder"),
                                    autocapitalization: .sentences,
                                    helperText: String(localized: "quickstart.signal.taipei.helper"),
                                    errorMessage: vm.signalHint)
                    }
                }

                // Gender + want-to-see — preserved from existing onboarding.
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

                // Three fit chips. Recommended but not required.
                conversationFitSection

                // Safety / anti-off-platform copy. Quiet but visible.
                safetyNote

                // 18+ gate.
                adultConfirmRow

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

    // MARK: - Conversation fit

    /// One card with the three fit-chip rows. Each row is independent;
    /// any combination of "selected / not selected" is allowed, so the
    /// user can skip individual chips.
    private var conversationFitSection: some View {
        GACard(kind: .standard, padding: GASpacing.xl) {
            VStack(alignment: .leading, spacing: GASpacing.lg) {
                VStack(alignment: .leading, spacing: GASpacing.xs) {
                    Text("quickstart.fit.title")
                        .font(GATypography.bodyEmphasized)
                        .foregroundStyle(GAColors.textPrimary)
                    Text("quickstart.fit.subtitle")
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                pickerSection(title: String(localized: "quickstart.fit.intent.label"),
                              options: ConnectionIntent.allCases,
                              selection: $vm.connectionIntent,
                              label: { $0.localizedTitle })
                pickerSection(title: String(localized: "quickstart.fit.rhythm.label"),
                              options: LifestyleRhythm.allCases,
                              selection: $vm.lifestyleRhythm,
                              label: { $0.localizedTitle })
                pickerSection(title: String(localized: "quickstart.fit.domain.label"),
                              options: ConversationDomain.allCases,
                              selection: $vm.conversationDomain,
                              label: { $0.localizedTitle })
            }
        }
    }

    // MARK: - Safety

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: GASpacing.sm) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GAColors.textSecondary)
                .padding(.top, 2)
            Text("safety.taipei.onboarding")
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, GASpacing.md)
        .padding(.vertical, GASpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GAColors.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                         style: .continuous))
    }

    // MARK: - Adult gate

    private var adultConfirmRow: some View {
        Button {
            vm.isAdultConfirmed.toggle()
        } label: {
            HStack(alignment: .top, spacing: GASpacing.sm) {
                Image(systemName: vm.isAdultConfirmed
                      ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(vm.isAdultConfirmed
                                     ? GAColors.accent
                                     : GAColors.textTertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("quickstart.adult.confirm")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textPrimary)
                    Text("quickstart.adult.title")
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Pickers

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
                        // Tap a selected tile to clear (toggle off) —
                        // critical for the fit chips, which are
                        // optional. Required pickers (gender / want)
                        // are still controlled by canSubmit.
                        if selection.wrappedValue == option {
                            selection.wrappedValue = nil
                        } else {
                            selection.wrappedValue = option
                        }
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
