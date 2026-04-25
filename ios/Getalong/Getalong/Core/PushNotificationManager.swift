import Foundation
import UserNotifications

final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()
    private override init() { super.init() }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    /// Stores the APNs device token alongside the user's profile via the
    /// `sendPushNotification` Edge Function or a dedicated profile update.
    func registerDeviceToken(_ token: Data) async {
        // TODO: send hex-encoded token to backend.
    }
}
