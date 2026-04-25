import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

/// Auth landing.
///
/// Design intent: editorial. Type carries the brand. The only colored
/// element is the primary action. No motifs, no frames, no gradients.
/// The four providers form a hairline-divided list below the primary,
/// not four boxed buttons.
struct SignInView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var appleNonce: String?

    var body: some View {
        ZStack {
            GAColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                Spacer(minLength: GASpacing.xxl)

                hero

                Spacer(minLength: 0)

                providers

                if let error = vm.errorMessage {
                    GAErrorBanner(message: error,
                                  onDismiss: { vm.errorMessage = nil })
                        .padding(.top, GASpacing.lg)
                }

                fineprint
                    .padding(.top, GASpacing.lg)
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, GASpacing.xl)
            .padding(.bottom, GASpacing.xl)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: GASpacing.xxl) {
            wordmark
            VStack(alignment: .leading, spacing: GASpacing.lg) {
                Text("Words\nthat travel.")
                    .font(GATypography.editorial)
                    .foregroundStyle(GAColors.textPrimary)
                    .lineSpacing(-2)
                    .kerning(-0.4)
                Text("A quieter way to meet — start with one sentence,\nsend a 15-second invite when something clicks.")
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textSecondary)
                    .lineSpacing(2)
            }
        }
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(GAColors.accent.opacity(0.30), lineWidth: 4)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(GAColors.accent)
                    .frame(width: 6, height: 6)
            }
            Text("GETALONG")
                .font(GATypography.micro)
                .tracking(2.4)
                .foregroundStyle(GAColors.textSecondary)
        }
    }

    // MARK: - Providers

    private var providers: some View {
        VStack(alignment: .leading, spacing: GASpacing.md) {
            primaryAppleButton

            VStack(spacing: 0) {
                providerRow(.google,
                            title: "Continue with Google",
                            systemImage: "g.circle.fill",
                            tint: Color(red: 0.93, green: 0.27, blue: 0.21))
                GAHairline()
                providerRow(.facebook,
                            title: "Continue with Facebook",
                            systemImage: "f.circle.fill",
                            tint: Color(red: 0.10, green: 0.36, blue: 0.78))
                GAHairline()
                providerRow(.twitter,
                            title: "Continue with X",
                            systemImage: "xmark",
                            tint: GAColors.textPrimary)
            }
            .padding(.top, GASpacing.lg)
        }
    }

    private var primaryAppleButton: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.makeNonce()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            guard let nonce = appleNonce else { return }
            Task { await vm.handleAppleResult(result, rawNonce: nonce) }
        }
        .signInWithAppleButtonStyle(appleStyle)
        .frame(height: GASpacing.controlHeight)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                    style: .continuous))
        .overlay(
            Group {
                if vm.workingProvider == .apple {
                    ZStack {
                        RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                         style: .continuous)
                            .fill(GAColors.background.opacity(0.6))
                        ProgressView().tint(GAColors.accent)
                    }
                }
            }
        )
    }

    private var appleStyle: SignInWithAppleButton.Style {
        // Black on light, white on dark — Apple HIG-correct.
        UITraitCollection.current.userInterfaceStyle == .dark ? .white : .black
    }

    @ViewBuilder
    private func providerRow(_ provider: AuthProvider,
                             title: String,
                             systemImage: String,
                             tint: Color) -> some View {
        GAProviderRow(
            title: title,
            systemImage: systemImage,
            iconTint: tint,
            isLoading: vm.workingProvider == provider,
            isDisabled: vm.isWorking && vm.workingProvider != provider
        ) {
            guard let anchor = activeAnchor() else { return }
            Task { await vm.signInWithOAuth(provider, anchor: anchor) }
        }
    }

    // MARK: - Fineprint

    private var fineprint: some View {
        Text("By continuing you confirm you are 18+ and accept Getalong's terms.")
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Window

    private func activeAnchor() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        ??
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first
    }

    // MARK: - Apple nonce

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
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    SignInView()
}
