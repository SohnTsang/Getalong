import SwiftUI

struct EditPreferencesSheet: View {
    let initial: Profile
    let onSaved: (Profile) -> Void
    let onClose: () -> Void

    @State private var gender: Gender?
    @State private var genderVisible: Bool
    @State private var interestedIn: InterestedInGender?
    @State private var phase: SavePhase = .editing

    init(initial: Profile,
         onSaved: @escaping (Profile) -> Void,
         onClose: @escaping () -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        self.onClose = onClose
        _gender = State(initialValue: initial.gender.flatMap(Gender.init(rawValue:)))
        _genderVisible = State(initialValue: initial.genderVisible)
        _interestedIn = State(initialValue:
            initial.interestedInGender.flatMap(InterestedInGender.init(rawValue:)))
    }

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.xl) {
                    genderCard
                    visibilityCard
                    interestedInCard

                    if case .error(let message) = phase {
                        GAErrorBanner(message: message,
                                      onDismiss: { phase = .editing })
                    }

                    Spacer(minLength: GASpacing.md)
                    saveButton
                }
            }
            .navigationTitle(String(localized: "profile.edit.preferences"))
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

    // MARK: - Sections

    private var genderCard: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.gender.label"))
            GACard {
                HStack(spacing: GASpacing.sm) {
                    ForEach(Gender.allCases) { g in
                        choiceChip(label: g.localizedLabel,
                                   selected: gender == g) {
                            gender = (gender == g ? nil : g)
                        }
                    }
                    choiceChip(label: String(localized: "profile.gender.placeholder"),
                               selected: gender == nil) {
                        gender = nil
                    }
                }
                .padding(.vertical, GASpacing.xs)
            }
        }
    }

    /// Visibility lives in its own card so it doesn't read as a sub-line
    /// of the gender chip row. Disabled when no gender is picked.
    private var visibilityCard: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.gender.visible"))
            GACard {
                Toggle(isOn: $genderVisible) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("profile.gender.visibleOnDiscover")
                            .font(GATypography.body)
                            .foregroundStyle(GAColors.textPrimary)
                        Text(genderVisible
                             ? String(localized: "profile.gender.visible")
                             : String(localized: "profile.gender.hidden"))
                            .font(GATypography.caption)
                            .foregroundStyle(GAColors.textTertiary)
                    }
                }
                .tint(GAColors.accent)
                .disabled(gender == nil)
                .opacity(gender == nil ? 0.5 : 1)
                .padding(.vertical, GASpacing.xs)
            }
        }
    }

    private var interestedInCard: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.gender.wantToSee"))
            GACard {
                HStack(spacing: GASpacing.sm) {
                    ForEach(InterestedInGender.allCases) { v in
                        choiceChip(label: v.localizedLabel,
                                   selected: interestedIn == v) {
                            interestedIn = (interestedIn == v ? nil : v)
                        }
                    }
                }
                .padding(.vertical, GASpacing.xs)
            }
        }
    }

    private func choiceChip(label: String,
                            selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(GATypography.callout)
                .foregroundStyle(selected ? GAColors.accentText : GAColors.textPrimary)
                .padding(.horizontal, GASpacing.md)
                .padding(.vertical, GASpacing.xs)
                .background(selected ? GAColors.accent : GAColors.surfaceRaised)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.clear : GAColors.border,
                        lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: -

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
        var patch = ProfilePatch()
        patch.gender             = gender?.rawValue
        // If gender is cleared, force visibility off so we never advertise
        // a hidden value.
        patch.genderVisible      = gender == nil ? false : genderVisible
        patch.interestedInGender = interestedIn?.rawValue
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
