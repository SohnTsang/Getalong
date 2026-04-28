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
    @EnvironmentObject private var session: SessionManager
    @StateObject private var missedTracker = MissedInvitesTracker()
    /// Lifted out of ChatsView so it can attach the moment the user
    /// signs in — chat-rooms realtime then runs app-wide and the list
    /// is already populated when the user first opens the tab.
    @StateObject private var chatsVM = ChatsViewModel()
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
                // Envelope icon reads as "an invite landed" more
                // clearly than the pulsing radio dots did. The
                // .badge() shows the receiver-side missed-invite
                // count; SwiftUI hides it automatically when zero.
                .tabItem { Label("tab.signals", systemImage: "envelope") }
                .badge(missedTracker.missedCount)
                .tag(Tab.invites)

            ChatsView()
                .tabItem { Label("tab.chats", systemImage: "ellipsis.message") }
                .tag(Tab.chats)

            ProfileView()
                .tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(GAColors.accent)
        .environmentObject(missedTracker)
        .environmentObject(chatsVM)
        // First-time permission ask, deferred until the user has reached
        // the main app — never on the auth screen and never on first launch.
        .task {
            await push.requestAuthorizationIfNeeded()
        }
        .task(id: currentUserId) {
            // Detach FIRST. Without this, sign-out left the previous
            // user's fallback polls + realtime listeners running
            // forever (the unstructured Tasks we spawn for attach
            // outlive the .task body's own lifecycle), and a user
            // switch produced double-listeners across both VMs.
            // detach() is idempotent and cheap.
            missedTracker.detach()
            chatsVM.detach()
            // Spawn unstructured Tasks so that SwiftUI tearing this
            // .task down (which it does on every dependency change /
            // body re-render) doesn't propagate Task.cancel() into
            // the realtime websocket subscribe — that's what produced
            // "realtime subscribe failed: CancellationError" on launch.
            if let uid = currentUserId {
                missedTracker.attach(userId: uid)
                Task { await chatsVM.attach(userId: uid) }
            }
        }
        .onChange(of: selection) { newTab in
            // Refresh the badge when the user opens the Invite tab so
            // the number is accurate the moment they land.
            if newTab == .invites { Task { await missedTracker.refresh() } }
            // The tab bar can rebuild items on selection changes, which
            // resets per-item offsets; re-apply on every tap.
            Self.nudgeTabBarBadgesInward()
        }
        .onAppear { Self.nudgeTabBarBadgesInward() }
        // Whenever the badge value changes the tab bar reapplies its
        // own layout — re-nudge so the new badge respects our offset.
        .onChange(of: missedTracker.missedCount) { _ in
            Self.nudgeTabBarBadgesInward()
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

    private var currentUserId: UUID? {
        if case .authenticated(let p) = session.state { return p.id }
        return nil
    }

    /// Tab bar gets a slightly raised, blurred surface that matches our
    /// background tokens — avoids the default chrome looking heavy in
    /// dark mode. Also nudges the system badge inward (default sits
    /// way out at the icon's top-right corner; –8pt horizontal pulls
    /// it back over the glyph so the digit reads as part of the tab,
    /// not floating off the side).
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

    /// Walks the active window hierarchy, finds the UITabBar SwiftUI's
    /// TabView is using, and pulls the badge inward on every item.
    /// `badgePositionAdjustment` is instance-only on `UITabBarItem`,
    /// so we can't set it through the global appearance proxy — we
    /// have to touch the live items after layout.
    fileprivate static func nudgeTabBarBadgesInward() {
        DispatchQueue.main.async {
            guard let tabBar = activeTabBar() else { return }
            let offset = UIOffset(horizontal: -10, vertical: 1)
            // ObjC property setter `setBadgePositionAdjustment:` is the
            // surviving selector on modern UIKit; the older
            // `…:forBarMetrics:` variant has been dropped. Use selector
            // forwarding so the Swift compiler doesn't have to know
            // about the bridge.
            let sel = NSSelectorFromString("setBadgePositionAdjustment:")
            for item in tabBar.items ?? [] {
                guard item.responds(to: sel) else { continue }
                guard let cls: AnyClass = object_getClass(item),
                      let imp = class_getMethodImplementation(cls, sel) else {
                    continue
                }
                typealias Fn = @convention(c) (AnyObject, Selector, UIOffset) -> Void
                let fn = unsafeBitCast(imp, to: Fn.self)
                fn(item, sel, offset)
            }
        }
    }

    private static func activeTabBar() -> UITabBar? {
        for scene in UIApplication.shared.connectedScenes {
            guard let win = (scene as? UIWindowScene)?.windows.first(where: \.isKeyWindow)
                ?? (scene as? UIWindowScene)?.windows.first else { continue }
            if let tab = findTabBar(in: win) { return tab }
        }
        return nil
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let tab = view as? UITabBar { return tab }
        for sub in view.subviews {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }
}
