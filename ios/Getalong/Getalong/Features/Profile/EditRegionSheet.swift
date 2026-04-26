import SwiftUI

struct EditRegionSheet: View {
    let initial: Profile
    let onSaved: (Profile) -> Void
    let onClose: () -> Void

    @State private var city: String
    @State private var country: String
    @State private var phase: SavePhase = .editing

    init(initial: Profile,
         onSaved: @escaping (Profile) -> Void,
         onClose: @escaping () -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        self.onClose = onClose
        _city    = State(initialValue: initial.city ?? "")
        _country = State(initialValue: initial.country ?? "")
    }

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    GATextField(
                        title: String(localized: "profile.city.label"),
                        text: $city,
                        placeholder: String(localized: "profile.city.placeholder")
                    )
                    if let m = cityError {
                        Text(m)
                            .font(GATypography.footnote)
                            .foregroundStyle(GAColors.danger)
                    }

                    GATextField(
                        title: String(localized: "profile.country.label"),
                        text: $country,
                        placeholder: String(localized: "profile.country.placeholder")
                    )
                    if let m = countryError {
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
            .navigationTitle(String(localized: "profile.edit.region"))
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

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedCountry: String {
        country.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cityError: String? {
        trimmedCity.count > ProfileLimits.cityMax
            ? String(localized: "profile.validation.cityTooLong") : nil
    }
    private var countryError: String? {
        trimmedCountry.count > ProfileLimits.countryMax
            ? String(localized: "profile.validation.countryTooLong") : nil
    }
    private var isValid: Bool {
        cityError == nil && countryError == nil
    }

    private func save() async {
        guard isValid, phase != .saving else { return }
        phase = .saving
        var patch = ProfilePatch()
        patch.city    = trimmedCity.isEmpty    ? nil : trimmedCity
        patch.country = trimmedCountry.isEmpty ? nil : trimmedCountry
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
