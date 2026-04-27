import SwiftUI

/// Region is GPS-driven only. The sheet exposes one toggle:
///
///   ON  – ask iOS for location → reverse-geocode → save city + country.
///   OFF – clear city + country on the user's profile.
///
/// We never let the user type a city/country manually; that was the
/// product call. iOS does not expose "the system's most recent
/// location" without active permission, so the off branch genuinely
/// shows nothing — there is no fallback we can use without a fresh
/// authorization grant.
struct EditRegionSheet: View {
    let initial: Profile
    let onSaved: (Profile) -> Void
    let onClose: () -> Void

    @StateObject private var location = LocationCoordinator()
    @State private var enabled: Bool
    @State private var phase: SavePhase = .editing

    init(initial: Profile,
         onSaved: @escaping (Profile) -> Void,
         onClose: @escaping () -> Void) {
        self.initial = initial
        self.onSaved = onSaved
        self.onClose = onClose
        // The toggle reflects whether we already have a saved region.
        let hasRegion = (initial.city?.isEmpty == false)
            || (initial.country?.isEmpty == false)
        _enabled = State(initialValue: hasRegion)
    }

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560, topPadding: GASpacing.xxl) {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    GACard {
                        VStack(alignment: .leading, spacing: GASpacing.md) {
                            Toggle(isOn: $enabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("profile.region.gps.toggle.title")
                                        .font(GATypography.body)
                                        .foregroundStyle(GAColors.textPrimary)
                                    Text("profile.region.gps.toggle.subtitle")
                                        .font(GATypography.footnote)
                                        .foregroundStyle(GAColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(GAColors.accent)
                            .onChange(of: enabled) { newValue in
                                Task { await onToggleChanged(newValue) }
                            }

                            if enabled {
                                statusRow
                            }
                        }
                        .padding(.vertical, GASpacing.xs)
                    }

                    if case .error(let message) = phase {
                        GAErrorBanner(message: message,
                                      onDismiss: { phase = .editing })
                    }

                    Spacer(minLength: GASpacing.md)
                }
            }
            .navigationTitle(String(localized: "profile.edit.region"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close"), action: onClose)
                }
            }
        }
    }

    // MARK: - Status row

    @ViewBuilder
    private var statusRow: some View {
        Divider().background(GAColors.border)
        switch location.phase {
        case .idle, .requestingPermission, .locating, .geocoding:
            HStack(spacing: GASpacing.sm) {
                ProgressView().controlSize(.small)
                Text(progressText)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textSecondary)
                Spacer()
            }
        case .success(let city, let country):
            // The profile was already updated; show the resolved value.
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(GAColors.success)
                Text(displayLocation(city: city, country: country))
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textPrimary)
                Spacer()
            }
        case .error(let m):
            HStack(spacing: GASpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(GAColors.danger)
                Text(m)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.danger)
                    .lineLimit(2)
                Spacer()
            }
        }
    }

    private var progressText: String {
        switch location.phase {
        case .requestingPermission: return String(localized: "profile.region.gps.requestingPermission")
        case .locating:             return String(localized: "profile.region.gps.locating")
        case .geocoding:            return String(localized: "profile.region.gps.geocoding")
        default:                    return String(localized: "profile.region.gps.locating")
        }
    }

    private func displayLocation(city: String?, country: String?) -> String {
        let parts = [city, country].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty
            ? String(localized: "profile.region.gps.noResult")
            : parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private func onToggleChanged(_ on: Bool) async {
        if on {
            await location.resolveRegion()
            // When CoreLocation reports success, push the values to
            // the profile.
            if case .success(let city, let country) = location.phase {
                await save(city: city, country: country)
            }
        } else {
            // OFF -> clear region.
            await save(city: nil, country: nil)
        }
    }

    private func save(city: String?, country: String?) async {
        var patch = ProfilePatch()
        patch.city    = city?.isEmpty == false ? city : nil
        patch.country = country?.isEmpty == false ? country : nil
        do {
            let updated = try await ProfileService.shared.updateMyProfile(patch)
            Haptics.success()
            onSaved(updated)
        } catch {
            phase = .error(String(localized: "profile.edit.error"))
            Haptics.error()
        }
    }
}
