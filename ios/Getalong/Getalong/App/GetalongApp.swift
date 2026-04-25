import SwiftUI

@main
struct GetalongApp: App {
    @StateObject private var session = SessionManager()
    @AppStorage("ga.appearance") private var appearanceRaw: String = GAAppearance.system.rawValue

    private var appearance: GAAppearance {
        GAAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(session)
                .preferredColorScheme(appearance.colorScheme)
                .tint(GAColors.accent)
                .task { await session.bootstrap() }
        }
    }
}
