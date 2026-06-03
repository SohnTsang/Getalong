import SwiftUI

/// Edit sheet for the Taipei beta "conversation fit" chips. Visually
/// matches the canonical profile edit sheets (EditPreferencesSheet,
/// EditProfileBasicsSheet, EditRegionSheet): NavigationStack shell,
/// inline navigation title, leading-toolbar Cancel, primary Save
/// button in the content. Each fit row is an optional chip — tapping
/// the selected chip clears it.
struct EditConversationFitSheet: View {
    let initial: Profile
    let onSaved: (Profile) -> Void
    let onClose: () -> Void

    @State private var intent: ConnectionIntent?
    @State private var rhythm: LifestyleRhythm?
    @State private var domain: ConversationDomain?
    @State private var phase: SavePhase = .editing

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
        NavigationStack {
            GAScreen(maxWidth: 560, topPadding: GASpacing.xxl) {
                VStack(alignment: .leading, spacing: GASpacing.xl) {
                    Text("profile.fit.subtitle")
                        .font(GATypography.callout)
                        .foregroundStyle(GAColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

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

                    if case .error(let message) = phase {
                        GAErrorBanner(message: message,
                                      onDismiss: { phase = .editing })
                    }

                    Spacer(minLength: GASpacing.md)
                    saveButton
                }
            }
            .navigationTitle(String(localized: "profile.fit.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onClose)
                        .disabled(phase == .saving)
                }
            }
            .interactiveDismissDisabled(phase == .saving)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    @ViewBuilder
    private func pickerSection<T: CaseIterable & Identifiable & Hashable>(
        title: String,
        options: T.AllCases,
        selection: Binding<T?>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: title)
            GACard {
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
                .padding(.vertical, GASpacing.xs)
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

    private var saveButton: some View {
        GAButton(
            title: String(localized: phase == .saving
                          ? "profile.edit.saving"
                          : "profile.edit.save"),
            kind: .primary,
            isLoading: phase == .saving,
            isDisabled: phase == .saving
        ) {
            Task { await save() }
        }
    }

    private func save() async {
        guard phase != .saving else { return }
        phase = .saving
        do {
            let updated = try await ProfileService.shared
                .updateMyConversationFit(intent: intent,
                                         rhythm: rhythm,
                                         domain: domain)
            Haptics.success()
            onSaved(updated)
        } catch let e as ProfileError {
            phase = .error(e.errorDescription ?? String(localized: "profile.edit.error"))
            Haptics.error()
        } catch {
            phase = .error(error.localizedDescription)
            Haptics.error()
        }
    }
}
