import SwiftUI
import UIKit

struct AppRouter: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                GALoadingView(label: "Getalong")
            case .unauthenticated:
                SignInView()
            case .profileSetupRequired(let userId):
                QuickStartProfileView(userId: userId)
            case .authenticated:
                MainTabView()
            case .banned:
                statusScreen(title: String(localized: "status.banned.title"),
                             message: String(localized: "status.banned.message"),
                             systemImage: "exclamationmark.shield")
            case .deleted:
                statusScreen(title: String(localized: "status.deleted.title"),
                             message: String(localized: "status.deleted.message"),
                             systemImage: "trash")
            case .error(let message):
                statusScreen(title: String(localized: "status.error.title"),
                             message: message,
                             systemImage: "wifi.exclamationmark")
            }
        }
        .animation(.snappy, value: stateToken)
    }

    private func statusScreen(title: String, message: String, systemImage: String) -> some View {
        GAScreen {
            GAEmptyState(title: title,
                         message: message,
                         systemImage: systemImage,
                         actionTitle: String(localized: "profile.signOut")) {
                Task { await session.signOut() }
            }
        }
    }

    private var stateToken: String {
        switch session.state {
        case .loading:               return "loading"
        case .unauthenticated:       return "unauth"
        case .profileSetupRequired:  return "setup"
        case .authenticated:         return "auth"
        case .banned:                return "banned"
        case .deleted:               return "deleted"
        case .error:                 return "error"
        }
    }
}

struct MainTabView: View {
    enum Tab: Hashable { case discover, invites, chats, profile }

    @EnvironmentObject private var push: PushNotificationManager
    @State private var selection: Tab = .discover

    init() {
        Self.applyTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $selection) {
            DiscoveryView()
                .tabItem { Label("tab.discover", systemImage: "sparkles") }
                .tag(Tab.discover)

            InvitesView()
                .tabItem { Label("tab.signals", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.invites)

            ChatsView()
                .tabItem { Label("tab.chats", systemImage: "ellipsis.message") }
                .tag(Tab.chats)

            ProfileView()
                .tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(GAColors.accent)
        // First-time permission ask, deferred until the user has reached
        // the main app — never on the auth screen and never on first launch.
        .task {
            await push.requestAuthorizationIfNeeded()
        }
        // Notification-tap routing. We currently route to a tab; deep-link
        // into a specific room is a TODO once ChatsView exposes selection.
        .onChange(of: push.pendingTap) { route in
            guard let route else { return }
            switch route {
            case .signals:
                selection = .invites
            case .chats:
                // TODO: deep-link to a specific chat room when ChatsView
                // accepts an external selection.
                selection = .chats
            }
            push.pendingTap = nil
        }
    }

    /// Tab bar gets a slightly raised, blurred surface that matches our
    /// background tokens — avoids the default chrome looking heavy in
    /// dark mode.
    private static func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.078, green: 0.094, blue: 0.129, alpha: 0.92)
                : UIColor(red: 0.984, green: 0.973, blue: 0.949, alpha: 0.92)
        }
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.18)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
