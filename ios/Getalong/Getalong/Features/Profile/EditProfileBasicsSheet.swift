import SwiftUI

/// Edit the one-line bio ("your line"). Display name was removed —
/// Getalong's profile no longer surfaces it anywhere user-facing.
struct EditProfileBasicsSheet: View {
    let initial: Profile
    let onSaved: (Profile) -> Void
    let onClose: () -> Void

    @State private var line: String
    @State private var phase: SavePhase = .editing

    init(initial: Profile,
         onSaved: @escaping (Profile) -> Void,
         onClose: @escaping () -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        self.onClose = onClose
        _line = State(initialValue: initial.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560, topPadding: GASpacing.xxl) {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    VStack(alignment: .leading, spacing: GASpacing.xs) {
                        Text("profile.signal.label")
                            .font(GATypography.sectionTitle)
                            .foregroundStyle(GAColors.textSecondary)
                            .textCase(.uppercase)
                        lineEditor
                        Text("\(trimmedLine.count) / \(ProfileLimits.signalMax)")
                            .font(GATypography.caption)
                            .foregroundStyle(lineCountColor)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if let m = lineError {
                        Text(m)
                            .font(GATypography.footnote)
                            .foregroundStyle(GAColors.danger)
                    } else if case .error(let message) = phase {
                        // Inline, no dismiss control. Clears the
                        // moment the user edits again (see
                        // .onChange below). Stays out of the way of
                        // the validation row above — only one of
                        // the two is ever visible.
                        Text(message)
                            .font(GATypography.footnote)
                            .foregroundStyle(GAColors.danger)
                    }

                    Spacer(minLength: GASpacing.md)
                    saveButton
                }
            }
            .navigationTitle(String(localized: "profile.edit.basics"))
            .onChange(of: line) { _ in
                // Clear any server error the moment the user edits;
                // their next save attempt deserves a fresh slate.
                if case .error = phase { phase = .editing }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onClose)
                        .disabled(phase == .saving)
                }
            }
            .interactiveDismissDisabled(phase == .saving)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var lineEditor: some View {
        ZStack(alignment: .topLeading) {
            if line.isEmpty {
                Text("profile.signal.placeholder")
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $line)
                .font(GATypography.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 64)
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

    private var trimmedLine: String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lineError: String? {
        if trimmedLine.isEmpty {
            return String(localized: "profile.validation.signalRequired")
        }
        if trimmedLine.count > ProfileLimits.signalMax {
            return String(localized: "profile.validation.signalTooLong")
        }
        return nil
    }

    /// Show the empty-line message only after the user has typed and
    /// emptied the field, so a fresh sheet doesn't open with a red
    /// validation error already present.
    private var isValid: Bool { lineError == nil }

    private var lineCountColor: Color {
        trimmedLine.count > ProfileLimits.signalMax
            ? GAColors.danger : GAColors.textTertiary
    }

    // MARK: - Save

    private func save() async {
        guard isValid, phase != .saving else { return }
        // Hard guard: never send an empty bio. The save button is
        // already disabled when this is true (isValid blocks it),
        // but keep the contract local so a missed binding can't
        // sneak an empty patch through.
        let value = trimmedLine
        guard !value.isEmpty else { return }
        phase = .saving
        var patch = ProfilePatch()
        patch.bio = value
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
