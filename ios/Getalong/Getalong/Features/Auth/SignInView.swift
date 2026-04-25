import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var appleNonce: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GASpacing.xl) {

                header

                modePicker

                fieldsCard

                if let info = vm.infoMessage {
                    GAErrorBanner(message: info)
                        .tint(GAColors.success)
                }

                if let error = vm.errorMessage {
                    GAErrorBanner(message: error,
                                  onDismiss: { vm.errorMessage = nil })
                }

                GAButton(title: vm.submitTitle,
                         kind: .primary,
                         isLoading: vm.isWorking,
                         isDisabled: !vm.canSubmit) {
                    Task { await vm.submit() }
                }

                appleButton

                toggleRow
            }
            .padding(.horizontal, GASpacing.lg)
            .padding(.vertical, GASpacing.xxl)
        }
        .background(GAColors.background.ignoresSafeArea())
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            Text("Getalong")
                .font(GATypography.display)
                .foregroundStyle(GAColors.textPrimary)
            Text("Connect through words first.")
                .font(GATypography.body)
                .foregroundStyle(GAColors.textSecondary)
        }
    }

    private var modePicker: some View {
        Picker("", selection: $vm.mode) {
            ForEach(AuthViewModel.Mode.allCases) { m in Text(m.rawValue).tag(m) }
        }
        .pickerStyle(.segmented)
    }

    private var fieldsCard: some View {
        GACard {
            VStack(spacing: GASpacing.md) {
                GATextField(title: "Email",
                            text: $vm.email,
                            placeholder: "you@example.com",
                            systemImage: "envelope",
                            keyboard: .emailAddress,
                            autocapitalization: .never)
                GATextField(title: "Password",
                            text: $vm.password,
                            placeholder: "At least 8 characters",
                            systemImage: "lock",
                            isSecure: true,
                            autocapitalization: .never)
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.makeNonce()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handleAppleResult(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous))
    }

    private var toggleRow: some View {
        HStack {
            Spacer()
            Button(action: vm.toggleMode) {
                Text(vm.mode == .signIn
                     ? "New here? Create an account"
                     : "Already have an account? Sign in")
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Apple sign-in

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce
            else {
                vm.errorMessage = AuthError.missingAppleIdentityToken.localizedDescription
                return
            }
            Task {
                vm.errorMessage = nil
                vm.isWorking = true
                defer { vm.isWorking = false }
                do {
                    try await AuthService.shared.signInWithApple(
                        idTokenJWT: token,
                        rawNonce: nonce
                    )
                } catch {
                    vm.errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            // User-cancelled is not an error worth surfacing.
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                vm.errorMessage = error.localizedDescription
            }
        }
    }

    private static func makeNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
            for byte in bytes where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    SignInView()
}
