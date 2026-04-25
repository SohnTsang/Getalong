import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

struct SignInView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var appleNonce: String?

    var body: some View {
        GAScreen(layout: .fixed,
                 maxWidth: 480,
                 horizontalPadding: GASpacing.screenHorizontal,
                 topPadding: GASpacing.xxxl,
                 bottomPadding: GASpacing.xxl) {

            VStack(alignment: .leading, spacing: GASpacing.xxl) {
                heroBlock
                hero
                Spacer(minLength: 0)
                authButtons
                if let error = vm.errorMessage {
                    GAErrorBanner(message: error,
                                  onDismiss: { vm.errorMessage = nil })
                }
                fineprint
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Hero

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            HStack(spacing: 6) {
                signalDot
                Text("GETALONG")
                    .font(GATypography.micro)
                    .tracking(2.0)
                    .foregroundStyle(GAColors.textTertiary)
            }
            .padding(.bottom, GASpacing.xs)

            Text("Meet through\nwords first.")
                .font(GATypography.largeTitle)
                .foregroundStyle(GAColors.textPrimary)
                .lineSpacing(2)

            Text("Send a 15-second invite when something clicks.")
                .font(GATypography.body)
                .foregroundStyle(GAColors.textSecondary)
        }
    }

    /// Abstract "two voices" motif — two overlapping word bubbles built
    /// from primitive shapes. No image assets, no gradient noise.
    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: GACornerRadius.xlarge, style: .continuous)
                .fill(GAColors.accentSoft)
                .frame(height: 132)
                .overlay(
                    RoundedRectangle(cornerRadius: GACornerRadius.xlarge,
                                     style: .continuous)
                        .strokeBorder(GAColors.accent.opacity(0.25), lineWidth: 1)
                )
                .overlay(
                    HStack(alignment: .bottom, spacing: -22) {
                        wordBubble(text: "Saw your post.",
                                   tint: GAColors.accent,
                                   fill: GAColors.surface)
                            .rotationEffect(.degrees(-3))
                        wordBubble(text: "Coffee tomorrow?",
                                   tint: GAColors.secondary,
                                   fill: GAColors.surface)
                            .rotationEffect(.degrees(3))
                            .padding(.top, 18)
                    }
                    .padding(.horizontal, GASpacing.lg),
                    alignment: .leading
                )
        }
    }

    private func wordBubble(text: String, tint: Color, fill: Color) -> some View {
        Text(text)
            .font(GATypography.callout)
            .foregroundStyle(GAColors.textPrimary)
            .padding(.horizontal, GASpacing.md)
            .padding(.vertical, GASpacing.sm)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
    }

    private var signalDot: some View {
        Circle()
            .fill(GAColors.accent)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(GAColors.accent.opacity(0.35), lineWidth: 4)
                    .frame(width: 14, height: 14)
            )
    }

    // MARK: - Auth buttons

    private var authButtons: some View {
        VStack(spacing: GASpacing.md) {
            appleButton
            GASocialButton(brand: .google,
                           isLoading: vm.workingProvider == .google,
                           isDisabled: vm.isWorking && vm.workingProvider != .google) {
                triggerOAuth(.google)
            }
            GASocialButton(brand: .facebook,
                           isLoading: vm.workingProvider == .facebook,
                           isDisabled: vm.isWorking && vm.workingProvider != .facebook) {
                triggerOAuth(.facebook)
            }
            GASocialButton(brand: .twitter,
                           isLoading: vm.workingProvider == .twitter,
                           isDisabled: vm.isWorking && vm.workingProvider != .twitter) {
                triggerOAuth(.twitter)
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.makeNonce()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            guard let nonce = appleNonce else { return }
            Task { await vm.handleAppleResult(result, rawNonce: nonce) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: GASpacing.controlHeight)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium, style: .continuous))
        .overlay(applePressOverlay)
    }

    @ViewBuilder
    private var applePressOverlay: some View {
        if vm.workingProvider == .apple {
            ZStack {
                RoundedRectangle(cornerRadius: GACornerRadius.medium, style: .continuous)
                    .fill(GAColors.background.opacity(0.6))
                ProgressView().tint(GAColors.accent)
            }
        }
    }

    private func triggerOAuth(_ provider: AuthProvider) {
        guard let anchor = activeAnchor() else { return }
        Task { await vm.signInWithOAuth(provider, anchor: anchor) }
    }

    // MARK: - Fineprint

    private var fineprint: some View {
        Text("By continuing you confirm you are 18+ and accept Getalong's terms.")
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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
