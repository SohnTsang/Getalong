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
                statusScreen(title: "Account unavailable",
                             message: "This account has been suspended.",
                             systemImage: "exclamationmark.shield")
            case .deleted:
                statusScreen(title: "Account deleted",
                             message: "This account is scheduled for deletion.",
                             systemImage: "trash")
            case .error(let message):
                statusScreen(title: "Something went wrong",
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
                         actionTitle: "Sign out") {
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

    @State private var selection: Tab = .discover

    init() {
        Self.applyTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $selection) {
            DiscoveryView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
                .tag(Tab.discover)

            InvitesView()
                .tabItem { Label("Signals", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.invites)

            ChatsView()
                .tabItem { Label("Chats", systemImage: "ellipsis.message") }
                .tag(Tab.chats)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(GAColors.accent)
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
