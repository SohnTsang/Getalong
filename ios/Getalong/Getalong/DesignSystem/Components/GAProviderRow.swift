import SwiftUI
import UIKit

/// A list-style auth row used as the secondary providers below the
/// primary Apple button. Hairline-divided, no boxed chrome — relies on
/// rhythm and typography. Inspired by editorial app auth (Threads,
/// Linear, Vercel).
///
/// `brandAsset` is preferred when available — when an image with that
/// name exists in the asset catalog (e.g., the official Google "G" or X
/// mark dropped into Assets.xcassets), it is rendered unmodified. If the
/// asset is missing the row falls back to the SF Symbol so builds still
/// work before the brand kits are added.
struct GAProviderRow: View {
    let title: String
    let systemImage: String
    var brandAsset: String? = nil
    var iconTint: Color = GAColors.textPrimary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !isLoading && !isDisabled { action() } }) {
            HStack(spacing: GASpacing.lg) {
                icon
                    .frame(width: 28, height: 28)
                Text(title)
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textPrimary)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(GAColors.textSecondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GAColors.textTertiary)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.5 : 1)
    }

    @ViewBuilder
    private var icon: some View {
        if let name = brandAsset, UIImage(named: name) != nil {
            // Brand kits ship the official mark; render unmodified.
            Image(name)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(iconTint)
        }
    }
}

/// Thin divider used between provider rows.
struct GAHairline: View {
    var body: some View {
        Rectangle()
            .fill(GAColors.border)
            .frame(height: 0.5)
    }
}
