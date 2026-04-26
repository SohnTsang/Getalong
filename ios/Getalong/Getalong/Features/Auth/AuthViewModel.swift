import Foundation
import SwiftUI
import AuthenticationServices

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var workingProvider: AuthProvider?
    @Published var errorMessage: String?

    var isWorking: Bool { workingProvider != nil }

    func handleAppleResult(
        _ result: Result<ASAuthorization, Error>,
        rawNonce: String
    ) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = AuthError.missingAppleIdentityToken.localizedDescription
                return
            }
            workingProvider = .apple
            defer { workingProvider = nil }
            do {
                try await AuthService.shared.signInWithApple(
                    idTokenJWT: token,
                    rawNonce: rawNonce
                )
            } catch let e as AuthError {
                errorMessage = e.localizedDescription
            } catch {
                GALog.auth.error("apple post-token error: \(error.localizedDescription)")
                errorMessage = String(localized: "error.generic")
            }
        case .failure(let error):
            errorMessage = Self.userMessage(forApple: error)
        }
    }

    func signInWithOAuth(_ provider: AuthProvider,
                         anchor: ASPresentationAnchor) async {
        errorMessage = nil
        workingProvider = provider
        defer { workingProvider = nil }
        do {
            try await AuthService.shared.signInWithOAuth(
                provider: provider,
                presentationAnchor: anchor
            )
        } catch AuthError.userCancelled {
            // silent
        } catch let e as AuthError {
            errorMessage = e.localizedDescription
        } catch {
            GALog.auth.error("oauth surfaced: \(error.localizedDescription)")
            errorMessage = String(localized: "error.generic")
        }
    }

    /// Translate an `ASAuthorizationError` from the Apple sign-in sheet
    /// into a calm, localized message. Anything other than user-cancel
    /// becomes a generic "couldn't sign in" so we never leak the raw
    /// "AuthorizationError error 1000" text into the UI.
    private static func userMessage(forApple error: Error) -> String? {
        let ns = error as NSError
        // ASAuthorizationError lives in its own domain; codes:
        //   1000 unknown, 1001 canceled, 1002 invalidResponse,
        //   1003 notHandled, 1004 failed, 1005 notInteractive
        switch ns.code {
        case ASAuthorizationError.canceled.rawValue:
            return nil   // silent — user backed out
        case ASAuthorizationError.notInteractive.rawValue:
            // Happens when the system can't present (e.g. background).
            GALog.auth.error("apple notInteractive")
            return String(localized: "error.generic")
        default:
            // 1000 unknown / 1002 invalidResponse / 1003 notHandled /
            // 1004 failed all mean "the system flow ended without a
            // valid credential". Most common real-world cause on a
            // device is a transient Apple ID hiccup; tell the user to
            // try again rather than dumping NSError text on screen.
            GALog.auth.error("apple authorization error code=\(ns.code) domain=\(ns.domain) desc=\(ns.localizedDescription)")
            return String(localized: "error.appleNoToken")
        }
    }
}
