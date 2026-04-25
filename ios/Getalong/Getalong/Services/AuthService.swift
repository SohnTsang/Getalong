import Foundation
import Supabase
import AuthenticationServices

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case missingAppleIdentityToken
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:               return "Please enter a valid email."
        case .weakPassword:               return "Password must be at least 8 characters."
        case .missingAppleIdentityToken:  return "Apple sign-in did not return an identity token."
        case .underlying(let m):          return m
        }
    }
}

@MainActor
final class AuthService {
    static let shared = AuthService()
    private init() {}

    // MARK: - Email

    func signUp(email: String, password: String) async throws {
        try Self.validate(email: email, password: password)
        do {
            _ = try await Supa.client.auth.signUp(email: email, password: password)
        } catch {
            throw AuthError.underlying(Self.message(from: error))
        }
    }

    func signIn(email: String, password: String) async throws {
        try Self.validate(email: email, password: password)
        do {
            _ = try await Supa.client.auth.signIn(email: email, password: password)
        } catch {
            throw AuthError.underlying(Self.message(from: error))
        }
    }

    func signOut() async throws {
        try await Supa.client.auth.signOut()
    }

    // MARK: - Sign in with Apple

    /// Pass the credential returned from `ASAuthorizationAppleIDProvider`.
    /// The caller is responsible for generating a nonce and passing the
    /// raw (un-hashed) version here so Supabase can validate the JWT.
    func signInWithApple(idTokenJWT: String, rawNonce: String) async throws {
        do {
            _ = try await Supa.client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idTokenJWT,
                    nonce: rawNonce
                )
            )
        } catch {
            throw AuthError.underlying(Self.message(from: error))
        }
    }

    // MARK: - Account deletion

    /// Soft-deletes the profile row. Hard-revoking the auth user requires
    /// an Edge Function with the service role; not built yet.
    func deleteAccount() async throws {
        guard let userId = try? await Supa.client.auth.session.user.id else {
            throw AuthError.underlying("Not signed in.")
        }
        try await ProfileService.shared.softDelete(userId: userId)
        try await Supa.client.auth.signOut()
    }

    // MARK: - Helpers

    private static func validate(email: String, password: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.contains(".") else { throw AuthError.invalidEmail }
        guard password.count >= 8 else { throw AuthError.weakPassword }
    }

    private static func message(from error: Error) -> String {
        // Supabase auth surfaces clean messages on the underlying error
        // already; just defer to its description.
        let raw = (error as NSError).localizedDescription
        return raw.isEmpty ? "Something went wrong. Please try again." : raw
    }
}
