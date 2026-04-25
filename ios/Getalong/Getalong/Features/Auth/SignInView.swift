import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

struct SignInView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var appleNonce: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GASpacing.xl) {

                header

                VStack(spacing: GASpacing.md) {
                    appleButton
                    socialButton(.google,   systemImage: "g.circle.fill")
                    socialButton(.facebook, systemImage: "f.circle.fill")
                    socialButton(.twitter,  systemImage: "xmark.app.fill")
                }

                if let error = vm.errorMessage {
                    GAErrorBanner(message: error,
                                  onDismiss: { vm.errorMessage = nil })
                }

                fineprint
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, GASpacing.lg)
            .padding(.vertical, GASpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(GAColors.background)
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
        .padding(.bottom, GASpacing.lg)
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
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous))
        .overlay(busyOverlay(for: .apple))
    }

    @ViewBuilder
    private func socialButton(_ provider: AuthProvider, systemImage: String) -> some View {
        Button {
            guard let anchor = activeAnchor() else { return }
            Task { await vm.signInWithOAuth(provider, anchor: anchor) }
        } label: {
            HStack(spacing: GASpacing.sm) {
                Image(systemName: systemImage)
                    .imageScale(.large)
                Text("Continue with \(provider.displayName)")
                    .font(GATypography.button)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(GAColors.surfaceMuted)
            .foregroundStyle(GAColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous)
                    .stroke(GAColors.border, lineWidth: 1)
            )
            .overlay(busyOverlay(for: provider))
        }
        .buttonStyle(.plain)
        .disabled(vm.isWorking)
        .opacity(vm.isWorking && vm.workingProvider != provider ? 0.5 : 1)
    }

    @ViewBuilder
    private func busyOverlay(for provider: AuthProvider) -> some View {
        if vm.workingProvider == provider {
            ZStack {
                RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous)
                    .fill(GAColors.background.opacity(0.6))
                ProgressView().tint(GAColors.accent)
            }
        }
    }

    private var fineprint: some View {
        Text("By continuing you agree that you are 18+ and accept Getalong's terms.")
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, GASpacing.lg)
    }

    // MARK: - Window resolution

    private func activeAnchor() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    // MARK: - Apple nonce helpers

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
