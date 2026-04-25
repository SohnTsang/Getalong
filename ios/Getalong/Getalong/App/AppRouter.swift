import SwiftUI

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
                GAEmptyState(
                    title: "Account unavailable",
                    message: "This account has been suspended.",
                    systemImage: "exclamationmark.shield",
                    actionTitle: "Sign out",
                    action: { Task { await session.signOut() } }
                )
                .padding(GASpacing.lg)
                .background(GAColors.background.ignoresSafeArea())
            case .deleted:
                GAEmptyState(
                    title: "Account deleted",
                    message: "This account is scheduled for deletion.",
                    systemImage: "trash",
                    actionTitle: "Sign out",
                    action: { Task { await session.signOut() } }
                )
                .padding(GASpacing.lg)
                .background(GAColors.background.ignoresSafeArea())
            case .error(let message):
                GAEmptyState(
                    title: "Something went wrong",
                    message: message,
                    systemImage: "wifi.exclamationmark",
                    actionTitle: "Sign out",
                    action: { Task { await session.signOut() } }
                )
                .padding(GASpacing.lg)
                .background(GAColors.background.ignoresSafeArea())
            }
        }
        .animation(.snappy, value: stateToken)
    }

    /// String token used purely to drive the SwiftUI animation between states.
    private var stateToken: String {
        switch session.state {
        case .loading:                    return "loading"
        case .unauthenticated:            return "unauth"
        case .profileSetupRequired:       return "setup"
        case .authenticated:              return "auth"
        case .banned:                     return "banned"
        case .deleted:                    return "deleted"
        case .error:                      return "error"
        }
    }
}

struct MainTabView: View {
    enum Tab: Hashable { case discover, invites, chats, profile }

    @State private var selection: Tab = .discover

    var body: some View {
        TabView(selection: $selection) {
            DiscoveryView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
                .tag(Tab.discover)

            InvitesView()
                .tabItem { Label("Invites", systemImage: "bolt.heart") }
                .tag(Tab.invites)

            ChatsView()
                .tabItem { Label("Chats", systemImage: "ellipsis.message") }
                .tag(Tab.chats)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
    }
}
