import SwiftUI
import Supabase

@main
struct GetalongApp: App {
    @UIApplicationDelegateAdaptor(GetalongAppDelegate.self) private var appDelegate
    @StateObject private var session = SessionManager()
    @StateObject private var push    = PushNotificationManager.shared
    @AppStorage("ga.appearance") private var appearanceRaw: String = GAAppearance.system.rawValue

    private var appearance: GAAppearance {
        GAAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(session)
                .environmentObject(push)
                .preferredColorScheme(appearance.colorScheme)
                .tint(GAColors.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GAColors.background.ignoresSafeArea())
                .task {
                    // Wipe any stranded media temp files from a
                    // previous session that crashed or got jetsammed
                    // mid-send. Cheap, expendable, runs once.
                    MediaTempFile.purgeAll()
                    await session.bootstrap()
                }
                .onOpenURL { url in
                    // Fallback for when an OAuth provider redirects via the
                    // system browser instead of completing inside
                    // ASWebAuthenticationSession.
                    Task {
                        try? await Supa.client.auth.session(from: url)
                    }
                }
        }
    }
}
