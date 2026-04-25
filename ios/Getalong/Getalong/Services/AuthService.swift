import Foundation
import Supabase
import AuthenticationServices

enum AuthError: LocalizedError {
    case missingAppleIdentityToken
    case userCancelled
    case oauthFailed(String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .missingAppleIdentityToken:  return "Apple sign-in did not return an identity token."
        case .userCancelled:              return "Sign-in was cancelled."
        case .oauthFailed(let m):         return m
        case .underlying(let m):          return m
        }
    }
}

/// Social sign-in providers that Getalong accepts.
enum AuthProvider: String, CaseIterable, Identifiable {
    case apple
    case google
    case facebook
    case twitter   // X

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:    return "Apple"
        case .google:   return "Google"
        case .facebook: return "Facebook"
        case .twitter:  return "X"
        }
    }

    /// Maps to the Supabase provider enum used by `signInWithOAuth`.
    var supabase: Provider {
        switch self {
        case .apple:    return .apple
        case .google:   return .google
        case .facebook: return .facebook
        case .twitter:  return .twitter
        }
    }
}

@MainActor
final class AuthService {
    static let shared = AuthService()
    private init() {}

    /// Custom URL scheme used for the OAuth redirect back to the app.
    /// Must match the URL Type registered in Info.plist AND the redirect URL
    /// added in the Supabase dashboard (Auth → URL Configuration).
    static let redirectURL = URL(string: "getalong://auth-callback")!

    // MARK: - Apple (native)

    /// Pass the credential returned from `ASAuthorizationAppleIDProvider`.
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

    // MARK: - Google / Facebook / X (web OAuth)

    /// Opens an `ASWebAuthenticationSession` against Supabase's OAuth
    /// authorize URL for the given provider, then exchanges the resulting
    /// `code` for a session.
    ///
    /// Caller must run this on the main actor and supply a presentation
    /// anchor (i.e. the active window scene). See `SignInView`.
    func signInWithOAuth(provider: AuthProvider,
                         presentationAnchor: ASPresentationAnchor) async throws {
        guard provider != .apple else {
            throw AuthError.oauthFailed("Use signInWithApple for Apple.")
        }

        // 1. Ask Supabase for the provider authorize URL.
        let authorizeURL: URL
        do {
            authorizeURL = try Supa.client.auth.getOAuthSignInURL(
                provider: provider.supabase,
                redirectTo: Self.redirectURL
            )
        } catch {
            throw AuthError.oauthFailed(Self.message(from: error))
        }

        // 2. Open the system browser sheet, wait for the redirect.
        let callbackURL: URL
        do {
            callbackURL = try await Self.startWebSession(
                url: authorizeURL,
                callbackScheme: Self.redirectURL.scheme!,
                anchor: presentationAnchor
            )
        } catch ASWebAuthenticationSessionError.canceledLogin {
            throw AuthError.userCancelled
        } catch {
            throw AuthError.oauthFailed(Self.message(from: error))
        }

        // 3. Hand the redirect URL to supabase-swift; it parses the code
        //    or implicit fragment and creates a session.
        do {
            try await Supa.client.auth.session(from: callbackURL)
        } catch {
            throw AuthError.oauthFailed(Self.message(from: error))
        }
    }

    // MARK: - Sign out / delete

    func signOut() async throws {
        try await Supa.client.auth.signOut()
    }

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

    private static func startWebSession(url: URL,
                                        callbackScheme: String,
                                        anchor: ASPresentationAnchor) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let presenter = WebAuthPresenter(anchor: anchor)
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error { cont.resume(throwing: error); return }
                guard let url else {
                    cont.resume(throwing: AuthError.oauthFailed("No callback URL."))
                    return
                }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            // Hold the presenter for the lifetime of the session.
            objc_setAssociatedObject(session, &Self.presenterKey, presenter, .OBJC_ASSOCIATION_RETAIN)
            session.start()
        }
    }

    private static var presenterKey: UInt8 = 0

    private static func message(from error: Error) -> String {
        let raw = (error as NSError).localizedDescription
        return raw.isEmpty ? "Something went wrong. Please try again." : raw
    }
}

/// Bridges `ASWebAuthenticationSession` to a SwiftUI window scene.
private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
