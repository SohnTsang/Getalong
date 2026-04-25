import SwiftUI

/// Top-level routing.
///
/// While auth/onboarding screens aren't built yet, the router shows the
/// main tab bar so the foundation is testable on-device.
struct AppRouter: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        switch session.state {
        case .loading:
            GALoadingView(label: "Getalong")
        case .banned:
            GAEmptyState(
                title: "Account unavailable",
                message: "This account has been suspended.",
                systemImage: "exclamationmark.shield"
            )
        case .deleted:
            GAEmptyState(
                title: "Account deleted",
                message: "This account is scheduled for deletion.",
                systemImage: "trash"
            )
        default:
            MainTabView()
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
