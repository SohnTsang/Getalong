import SwiftUI

/// Edit display name + one-line signal (bio).
struct EditProfileBasicsSheet: View {
    let initial: Profile
    let onSaved: (Profile) -> Void
    let onClose: () -> Void

    @State private var displayName: String
    @State private var signal: String
    @State private var phase: SavePhase = .editing

    init(initial: Profile,
         onSaved: @escaping (Profile) -> Void,
         onClose: @escaping () -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        self.onClose = onClose
        _displayName = State(initialValue: initial.displayName)
        _signal      = State(initialValue: initial.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    GATextField(
                        title: String(localized: "profile.displayName.label"),
                        text: $displayName,
                        placeholder: String(localized: "profile.displayName.placeholder")
                    )
                    if let m = displayNameError {
                        Text(m)
                            .font(GATypography.footnote)
                            .foregroundStyle(GAColors.danger)
                    }

                    VStack(alignment: .leading, spacing: GASpacing.xs) {
                        Text("profile.signal.label")
                            .font(GATypography.sectionTitle)
                            .foregroundStyle(GAColors.textSecondary)
                            .textCase(.uppercase)
                        signalEditor
                        Text("\(trimmedSignal.count) / \(ProfileLimits.signalMax)")
                            .font(GATypography.caption)
                            .foregroundStyle(signalCountColor)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if let m = signalError {
                        Text(m)
                            .font(GATypography.footnote)
                            .foregroundStyle(GAColors.danger)
                    }

                    if case .error(let message) = phase {
                        GAErrorBanner(message: message,
                                      onDismiss: { phase = .editing })
                    }

                    Spacer(minLength: GASpacing.md)
                    saveButton
                }
            }
            .navigationTitle(String(localized: "profile.edit.basics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onClose)
                        .disabled(phase == .saving)
                }
            }
            .interactiveDismissDisabled(phase == .saving)
        }
    }

    private var signalEditor: some View {
        ZStack(alignment: .topLeading) {
            if signal.isEmpty {
                Text("profile.signal.placeholder")
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $signal)
                .font(GATypography.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 120)
        }
        .background(GAColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.large,
                             style: .continuous)
                .strokeBorder(GAColors.border, lineWidth: 0.75)
        )
    }

    private var saveButton: some View {
        GAButton(
            title: String(localized: phase == .saving
                          ? "profile.edit.saving"
                          : "profile.edit.save"),
            kind: .primary,
            isLoading: phase == .saving,
            isDisabled: phase == .saving || !isValid
        ) {
            Task { await save() }
        }
    }

    // MARK: - Validation

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedSignal: String {
        signal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayNameError: String? {
        if trimmedDisplayName.isEmpty {
            return String(localized: "profile.validation.displayNameRequired")
        }
        if trimmedDisplayName.count > ProfileLimits.displayNameMax {
            return String(localized: "profile.validation.displayNameTooLong")
        }
        return nil
    }

    private var signalError: String? {
        if trimmedSignal.count > ProfileLimits.signalMax {
            return String(localized: "profile.validation.signalTooLong")
        }
        return nil
    }

    private var isValid: Bool {
        displayNameError == nil && signalError == nil
    }

    private var signalCountColor: Color {
        trimmedSignal.count > ProfileLimits.signalMax
            ? GAColors.danger : GAColors.textTertiary
    }

    // MARK: - Save

    private func save() async {
        guard isValid, phase != .saving else { return }
        phase = .saving
        var patch = ProfilePatch()
        patch.displayName = trimmedDisplayName
        patch.bio = trimmedSignal.isEmpty ? nil : trimmedSignal
        do {
            let updated = try await ProfileService.shared.updateMyProfile(patch)
            Haptics.success()
            onSaved(updated)
        } catch let e as ProfileError {
            phase = .error(e.errorDescription ?? String(localized: "profile.edit.error"))
            Haptics.error()
        } catch {
            phase = .error(String(localized: "profile.edit.error"))
            Haptics.error()
        }
    }
}

enum SavePhase: Equatable {
    case editing
    case saving
    case error(String)
}
