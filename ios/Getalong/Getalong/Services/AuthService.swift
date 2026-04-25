import Foundation

/// Wraps Supabase auth (email + Sign in with Apple).
@MainActor
final class AuthService {
    static let shared = AuthService()
    private init() {}

    func signInWithEmail(email: String, password: String) async throws {
        // TODO
    }

    func signUpWithEmail(email: String, password: String) async throws {
        // TODO
    }

    func signInWithApple(idTokenJWT: String, nonce: String) async throws {
        // TODO
    }

    func signOut() async throws {
        // TODO
    }

    func deleteAccount() async throws {
        // Backend should soft-delete the profile then revoke auth user.
        // TODO
    }
}
