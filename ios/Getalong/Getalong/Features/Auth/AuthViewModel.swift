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
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
