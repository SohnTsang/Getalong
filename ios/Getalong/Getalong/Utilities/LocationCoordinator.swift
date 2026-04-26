import Foundation
import CoreLocation

/// Wraps `CLLocationManager` + `CLGeocoder` for the single use-case
/// Getalong has: ask for one-shot foreground location, reverse-geocode
/// it to (city, country), hand the result back. Designed to be created
/// per-sheet — the EditRegionSheet owns one and discards on dismiss.
@MainActor
final class LocationCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {

    enum AuthState: Equatable {
        case notDetermined
        case authorized
        case denied   // user said no, or restricted by parental control
    }

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case locating
        case geocoding
        case success(city: String?, country: String?)
        case error(String)
    }

    @Published private(set) var authState: AuthState = .notDetermined
    @Published private(set) var phase: Phase = .idle

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var awaitingFix = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        refreshAuthState()
    }

    /// Returns the current city/country pair or throws on failure.
    /// Drives `phase` so the UI can show progress.
    func resolveRegion() async {
        refreshAuthState()
        switch authState {
        case .notDetermined:
            phase = .requestingPermission
            manager.requestWhenInUseAuthorization()
            // requestLocation() is fired by didChangeAuthorization
            return
        case .denied:
            phase = .error(String(localized: "profile.region.gps.permissionDenied"))
            return
        case .authorized:
            beginLocationFetch()
        }
    }

    private func beginLocationFetch() {
        awaitingFix = true
        phase = .locating
        manager.requestLocation()
    }

    private func refreshAuthState() {
        switch manager.authorizationStatus {
        case .notDetermined:
            authState = .notDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            authState = .authorized
        case .denied, .restricted:
            authState = .denied
        @unknown default:
            authState = .denied
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refreshAuthState()
            switch authState {
            case .authorized:
                if awaitingFix || phase == .requestingPermission {
                    beginLocationFetch()
                }
            case .denied:
                phase = .error(String(localized: "profile.region.gps.permissionDenied"))
                awaitingFix = false
            case .notDetermined:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            awaitingFix = false
            phase = .geocoding
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                let placemark = placemarks.first
                phase = .success(
                    city:    placemark?.locality ?? placemark?.subAdministrativeArea,
                    country: placemark?.country
                )
            } catch {
                GALog.profile.error("reverse geocode failed: \(error.localizedDescription)")
                phase = .error(String(localized: "profile.region.gps.lookupFailed"))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            awaitingFix = false
            GALog.profile.error("CLLocationManager error: \(error.localizedDescription)")
            phase = .error(String(localized: "profile.region.gps.lookupFailed"))
        }
    }
}
