import Foundation
import Supabase
import SwiftUI

enum SessionState: Equatable {
    case loading
    case unauthenticated
    case profileSetupRequired(userId: UUID)
    case authenticated(profile: Profile)
    case banned
    case deleted
    case error(String)
}

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var state: SessionState = .loading

    private var authListener: Task<Void, Never>?

    func bootstrap() async {
        // Resolve any cached session, then start listening for changes.
        do {
            if let session = try? await Supa.client.auth.session {
                await resolve(userId: session.user.id)
            } else {
                state = .unauthenticated
            }
        }

        startListening()
    }

    private func startListening() {
        authListener?.cancel()
        authListener = Task { [weak self] in
            for await change in Supa.client.auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
                    if let user = change.session?.user {
                        await self.resolve(userId: user.id)
                    }
                case .signedOut:
                    self.state = .unauthenticated
                default:
                    break
                }
            }
        }
    }

    /// Looks up the profile row for `userId`. If absent, signals onboarding.
    func resolve(userId: UUID) async {
        do {
            let profile: Profile? = try await ProfileService.shared.fetchProfile(id: userId)
            if let profile {
                if profile.isBanned {
                    state = .banned
                } else if profile.deletedAt != nil {
                    state = .deleted
                } else {
                    state = .authenticated(profile: profile)
                }
            } else {
                state = .profileSetupRequired(userId: userId)
            }
        } catch {
            GALog.auth.error("resolve(userId:) failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    func setAuthenticated(_ profile: Profile) {
        state = .authenticated(profile: profile)
    }

    func signOut() async {
        do {
            try await Supa.client.auth.signOut()
            state = .unauthenticated
        } catch {
            GALog.auth.error("signOut failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// Convenience for the first-run setup screen.
    var pendingUserId: UUID? {
        if case .profileSetupRequired(let id) = state { return id }
        return nil
    }

    deinit { authListener?.cancel() }
}
