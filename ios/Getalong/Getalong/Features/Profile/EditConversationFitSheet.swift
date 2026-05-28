import SwiftUI

/// Edit sheet for the Taipei beta "conversation fit" chips. Each row
/// is a tappable FlowLayout of pickerTiles; selecting a tile sets the
/// value, tapping the selected tile clears it (so the chip is truly
/// optional even after the user has touched it). Save persists via
/// `ProfileService.updateMyProfile`; sensitive fields are still
/// locked at the DB level.
struct EditConversationFitSheet: View {
    let initial: Profile
    let onSaved: (Profile) -> Void
    let onClose: () -> Void

    @State private var intent: ConnectionIntent?
    @State private var rhythm: LifestyleRhythm?
    @State private var domain: ConversationDomain?
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    init(initial: Profile,
         onSaved: @escaping (Profile) -> Void,
         onClose: @escaping () -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        self.onClose = onClose
        _intent = State(initialValue: initial.connectionIntentTyped)
        _rhythm = State(initialValue: initial.lifestyleRhythmTyped)
        _domain = State(initialValue: initial.conversationDomainTyped)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GASpacing.lg) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    pickerSection(title: String(localized: "quickstart.fit.intent.label"),
                                  options: ConnectionIntent.allCases,
                                  selection: $intent,
                                  label: { $0.localizedTitle })
                    pickerSection(title: String(localized: "quickstart.fit.rhythm.label"),
                                  options: LifestyleRhythm.allCases,
                                  selection: $rhythm,
                                  label: { $0.localizedTitle })
                    pickerSection(title: String(localized: "quickstart.fit.domain.label"),
                                  options: ConversationDomain.allCases,
                                  selection: $domain,
                                  label: { $0.localizedTitle })
                    if let err = errorMessage {
                        GAErrorBanner(message: err,
                                      onDismiss: { errorMessage = nil })
                    }
                }
            }
            GAButton(title: String(localized: "common.save"),
                     kind: .primary,
                     isLoading: isSaving) {
                Task { await save() }
            }
        }
        .padding(.top, GASafetySheet.topPadding)
        .padding(.horizontal, GASpacing.lg)
        .padding(.bottom, GASpacing.lg)
        .background(GAColors.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("profile.fit.edit.title")
                    .font(GATypography.title)
                    .foregroundStyle(GAColors.textPrimary)
                Text("profile.fit.subtitle")
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GAColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(GAColors.surfaceRaised, in: Circle())
            }
            .accessibilityLabel(String(localized: "common.cancel"))
            .disabled(isSaving)
        }
    }

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

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await ProfileService.shared
                .updateMyConversationFit(intent: intent,
                                         rhythm: rhythm,
                                         domain: domain)
            onSaved(updated)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
