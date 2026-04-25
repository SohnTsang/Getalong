import Foundation
import SwiftUI

enum SessionState: Equatable {
    case unauthenticated
    case onboardingRequired(userId: UUID)
    case authenticated(profile: Profile)
    case banned
    case deleted
    case loading
}

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var state: SessionState = .loading

    /// Wires up auth listening once `supabase-swift` is added.
    func bootstrap() async {
        // Placeholder: real implementation will subscribe to
        // `client.auth.onAuthStateChange` and resolve current profile.
        self.state = .unauthenticated
    }

    func signOut() async {
        // Placeholder
        self.state = .unauthenticated
    }
}
