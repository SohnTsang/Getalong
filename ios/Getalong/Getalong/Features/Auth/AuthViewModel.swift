import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .signIn
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isWorking: Bool = false
    @Published var errorMessage: String?
    /// Set when sign-up returns a session that requires email verification.
    @Published var infoMessage: String?

    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        errorMessage = nil
        infoMessage = nil
    }

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && password.count >= 8
        && !isWorking
    }

    var submitTitle: String {
        mode == .signIn ? "Sign in" : "Create account"
    }

    func submit() async {
        errorMessage = nil
        infoMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            switch mode {
            case .signIn:
                try await AuthService.shared.signIn(email: email, password: password)
            case .signUp:
                try await AuthService.shared.signUp(email: email, password: password)
                // If the project has email confirmation on, the auth state
                // listener won't fire until the user confirms. Surface a
                // hint so they know to check their inbox.
                if (try? await Supa.client.auth.session) == nil {
                    infoMessage = "Check your email to confirm your account, then sign in."
                    mode = .signIn
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
