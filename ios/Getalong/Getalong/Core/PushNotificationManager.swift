import Foundation
import UIKit
import UserNotifications
import Supabase

extension Notification.Name {
    /// Posted on the main thread by `PushNotificationManager` when an
    /// APNs payload of type `live_signal_received` arrives while the
    /// app is in the foreground. `MissedInvitesTracker` listens and
    /// triggers an immediate refresh so the navbar tint comes up the
    /// moment the push lands — independent of the realtime websocket
    /// (which can fail with CancellationError at sign-in and only
    /// recovers on its own retry path).
    static let gaLiveInvitePushReceived = Notification.Name(
        "ga.push.liveInviteReceived"
    )
}

/// Coordinates APNs registration, token upload to the Getalong backend, and
/// notification-tap routing for in-app navigation.
///
/// Lifecycle:
///   1. `GetalongAppDelegate` sets `UNUserNotificationCenter.delegate = .shared`
///      on launch (cheap, no permission prompt yet).
///   2. After the user finishes profile setup or otherwise reaches the main
///      app, call `requestAuthorizationIfNeeded()` to ask for permission and
///      register with APNs.
///   3. APNs hands the device token to `application(_:didRegisterFor…)`,
///      which forwards it to `register(deviceToken:)`. We hex-encode and
///      upload via the `registerDeviceToken` Edge Function.
///   4. Notification taps are surfaced via the `NotificationTapRoute`
///      publisher; `MainTabView` listens and switches tabs.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    /// Routes a notification tap toward a tab. UI listens via `@Published`.
    enum TapRoute: Equatable {
        case signals
        case chats(roomId: UUID?)
    }

    @Published var pendingTap: TapRoute?

    private override init() { super.init() }

    /// Wire up the user-notification delegate. Safe to call without
    /// triggering the permission prompt.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    /// Asks the system whether we already asked. If not asked yet, asks now;
    /// otherwise just registers if already authorized.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                if granted {
                    await registerForRemoteNotifications()
                }
            } catch {
                GALog.push.error("authorization request failed: \(error.localizedDescription)")
            }
        case .authorized, .provisional, .ephemeral:
            await registerForRemoteNotifications()
        case .denied:
            // User said no — respect it. They can re-enable in iOS Settings.
            break
        @unknown default:
            break
        }
    }

    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Token upload

    /// Called from the AppDelegate APNs callbacks.
    func register(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        GALog.push.debug("APNs token received (\(hex.count) hex chars)")
        Task { await uploadToken(hex) }
    }

    func registrationFailed(error: Error) {
        GALog.push.error("APNs registration failed: \(error.localizedDescription)")
    }

    private struct RegisterBody: Encodable {
        let token: String
        let platform: String
        let environment: String
        let app_version: String?
        let locale: String?
        let timezone: String?
        let device_id: String?
    }

    private func uploadToken(_ hex: String) async {
        guard hex.count > 0 else { return }
        do {
            // No durable session means no-op; we'll re-try after sign-in.
            let session = try? await Supa.client.auth.session
            guard session != nil else {
                GALog.push.debug("skip token upload: no session yet")
                return
            }

            let body = RegisterBody(
                token: hex,
                platform: "ios",
                environment: Self.apnsEnvironment(),
                app_version: Bundle.main.infoDictionary?[
                    "CFBundleShortVersionString"
                ] as? String,
                locale: Locale.current.identifier,
                timezone: TimeZone.current.identifier,
                device_id: UIDevice.current.identifierForVendor?.uuidString
            )

            _ = try await Supa.invokeRaw("registerDeviceToken", body: body)
            GALog.push.info("device token registered")
        } catch {
            GALog.push.error("registerDeviceToken failed: \(error.localizedDescription)")
        }
    }

    /// Best-effort detection of the APNs environment based on the
    /// embedded provisioning profile / entitlement. We default to
    /// "sandbox" because debug builds and TestFlight both ship with the
    /// development entitlement; production builds installed from the App
    /// Store ship with `aps-environment = production`.
    private static func apnsEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        // Inspect the embedded provisioning profile if present.
        if let url = Bundle.main.url(
            forResource: "embedded", withExtension: "mobileprovision"
        ),
           let data = try? Data(contentsOf: url),
           let raw = String(data: data, encoding: .ascii),
           raw.contains("<key>aps-environment</key>") &&
            raw.contains("<string>production</string>") {
            return "production"
        }
        return "sandbox"
        #endif
    }

    // MARK: - Trigger from a known UI moment

    /// Re-runs the registration call after sign-in completes, in case we
    /// already had APNs authorization but failed to upload the token while
    /// signed out.
    func refreshAfterSignIn() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        else { return }
        await registerForRemoteNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Foreground presentation: show banner + sound, no badge
    /// increment. Suppressed entirely when the incoming push targets
    /// the chat room the user is currently sitting in — matches the
    /// iMessage / WhatsApp pattern where you don't get a banner for
    /// the conversation that's already open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let roomString = (userInfo["room_id"] as? String)
            ?? (userInfo["chat_room_id"] as? String)
        let pushRoom = roomString.flatMap(UUID.init(uuidString:))
        let pushType = userInfo["type"] as? String
        Task { @MainActor in
            // Live-invite pushes drive the navbar accent tint. Post
            // before the banner decision so the tracker refreshes even
            // when the user is sitting on a tab that suppresses the
            // banner. Refreshing is idempotent and coalesced inside
            // the tracker, so it's safe to fire on every live push.
            if pushType == "live_signal_received" {
                NotificationCenter.default.post(
                    name: .gaLiveInvitePushReceived, object: nil
                )
            }
            if let pushRoom, pushRoom == ChatPresence.shared.currentRoomId {
                completionHandler([])
            } else {
                completionHandler([.banner, .sound, .list])
            }
        }
    }

    /// Tap handling.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let route = PushNotificationManager.parseTapRouteSync(userInfo: userInfo)
        Task { @MainActor in
            self.pendingTap = route
            completionHandler()
        }
    }

    nonisolated static func parseTapRouteSync(userInfo: [AnyHashable: Any]) -> TapRoute {
        let type = (userInfo["type"] as? String) ?? ""
        switch type {
        case "live_signal_received":
            return .signals
        case "conversation_started", "new_message":
            let roomString = userInfo["chat_room_id"] as? String
                ?? userInfo["room_id"] as? String
            return .chats(roomId: roomString.flatMap(UUID.init(uuidString:)))
        default:
            return .chats(roomId: nil)
        }
    }
}
