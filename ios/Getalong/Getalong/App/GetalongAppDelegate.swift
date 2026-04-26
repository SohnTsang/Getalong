import UIKit

/// Bridges UIKit-only APNs callbacks into our SwiftUI app.
final class GetalongAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Wire the UN delegate immediately. This does NOT trigger the
        // permission prompt — that's gated by `requestAuthorizationIfNeeded()`.
        Task { @MainActor in
            PushNotificationManager.shared.configure()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.register(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.registrationFailed(error: error)
        }
    }
}
