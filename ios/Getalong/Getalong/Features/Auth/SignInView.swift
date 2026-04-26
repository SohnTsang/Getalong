import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

/// Auth landing.
///
/// The hero **shows** the product mechanic instead of describing it: a
/// realistic mock live-invite card with a ticking 15-second ring + a
/// quoted message. Below it, two editorial lines land the takeaway. The
/// auth list lives at the bottom — primary Apple, then a hairline list
/// for the other providers.
struct SignInView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var appleNonce: String?

    var body: some View {
        ZStack {
            GAColors.background.ignoresSafeArea()

            // Two-anchor layout: top block (wordmark + hero) sits up
            // top, bottom block (providers + errors + fineprint) sits
            // at the bottom of the safe area. The gap between them is
            // a *capped* Spacer — it grows with available room so the
            // buttons stay near the bottom on tall phones, but never
            // exceeds `maxGap` so the hero never feels orphaned.
            VStack(alignment: .leading, spacing: 0) {

                centeredWordmark
                    .padding(.top, GASpacing.lg)
                    .padding(.bottom, GASpacing.xxl)

                hero

                Spacer(minLength: GASpacing.xl)
                    .frame(maxHeight: 120)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, GASpacing.xl)
            .padding(.bottom, GASpacing.xl)
        }
    }

    // MARK: - Wordmark

    /// Centered, prominent brand block. The "signal dot" (concentric
    /// circle + filled core) is the brand mark; the wordmark sits below.
    private var centeredWordmark: some View {
        VStack(spacing: GASpacing.md) {
            ZStack {
                Circle()
                    .stroke(GAColors.accent.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                Circle()
                    .stroke(GAColors.accent.opacity(0.32), lineWidth: 6)
                    .frame(width: 38, height: 38)
                Circle()
                    .fill(GAColors.accent)
                    .frame(width: 14, height: 14)
            }
            Text("GETALONG")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .tracking(3.6)
                .foregroundStyle(GAColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    /// Product moment as the hero. Two stacked beats:
    /// 1. A teaser card that *looks like* a real incoming invite.
    /// 2. Two editorial lines naming the value.
    private var hero: some View {
        VStack(alignment: .leading, spacing: GASpacing.xl) {
            inviteTeaser
            editorialLines
        }
    }

    /// The teaser shows the core unit of Getalong: one small signal —
    /// no avatar, no handle, no region. Just the line and a quiet LIVE
    /// indicator. Identical structure to the Discovery card.
    private var inviteTeaser: some View {
        HStack(alignment: .top, spacing: GASpacing.md) {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                GenderBadge(kind: .female)
                Text("auth.hero.teaser.message")
                    .font(GATypography.bodyEmphasized)
                    .foregroundStyle(GAColors.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                PulsingCountdownRing(total: 15, size: 36, lineWidth: 2.5)
                Text("auth.hero.teaser.live")
                    .font(GATypography.micro)
                    .tracking(1.4)
                    .foregroundStyle(GAColors.textTertiary)
            }
        }
        .padding(GASpacing.xl)
        .background(GAColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.large,
                             style: .continuous)
                .strokeBorder(GenderBadge.Kind.female.tint.opacity(0.30),
                              lineWidth: 0.25)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 6)
    }

    private var editorialLines: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text("auth.hero.title.line1")
                    .font(GATypography.heroSerif)
                    .foregroundStyle(GAColors.textPrimary)
                    .lineSpacing(-2)
                    .kerning(-0.3)
                Text("auth.hero.title.line2")
                    .font(GATypography.heroSerif)
                    .foregroundStyle(GAColors.accent)
                    .lineSpacing(-2)
                    .kerning(-0.3)
            }
            Text("auth.hero.subtitle")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Providers

    private var providers: some View {
        VStack(alignment: .leading, spacing: GASpacing.md) {
            primaryAppleButton

            VStack(spacing: 0) {
                providerRow(.google,
                            title: String(localized: "auth.cta.google"),
                            systemImage: "g.circle.fill",
                            brandAsset: "BrandGoogleG",
                            iconSize: 32,
                            tint: Color(red: 0.93, green: 0.27, blue: 0.21))
                GAHairline()
                providerRow(.twitter,
                            title: String(localized: "auth.cta.x"),
                            systemImage: "xmark",
                            brandAsset: "BrandX",
                            iconSize: 22,
                            tint: GAColors.textPrimary)
            }
            .padding(.top, GASpacing.sm)
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
        // SignInWithAppleButton sizes its label to fit the height —
        // 44pt brings the title in line with the secondary provider rows
        // without making the button feel cramped.
        .frame(height: 44)
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
        UITraitCollection.current.userInterfaceStyle == .dark ? .white : .black
    }

    @ViewBuilder
    private func providerRow(_ provider: AuthProvider,
                             title: String,
                             systemImage: String,
                             brandAsset: String? = nil,
                             iconSize: CGFloat = 28,
                             tint: Color) -> some View {
        GAProviderRow(
            title: title,
            systemImage: systemImage,
            brandAsset: brandAsset,
            iconTint: tint,
            iconSize: iconSize,
            isLoading: vm.workingProvider == provider,
            isDisabled: vm.isWorking && vm.workingProvider != provider
        ) {
            guard let anchor = activeAnchor() else { return }
            Task { await vm.signInWithOAuth(provider, anchor: anchor) }
        }
    }

    // MARK: - Fineprint

    private var fineprint: some View {
        Text("auth.terms.18plus")
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
