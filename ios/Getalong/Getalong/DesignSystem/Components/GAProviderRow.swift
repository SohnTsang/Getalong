import SwiftUI

/// A list-style auth row used as the secondary providers below the
/// primary Apple button. Hairline-divided, no boxed chrome — relies on
/// rhythm and typography. Inspired by editorial app auth (Threads,
/// Linear, Vercel).
struct GAProviderRow: View {
    let title: String
    let systemImage: String
    var iconTint: Color = GAColors.textPrimary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !isLoading && !isDisabled { action() } }) {
            HStack(spacing: GASpacing.lg) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconTint)
                    .frame(width: 22, height: 22)
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
}

/// Thin divider used between provider rows.
struct GAHairline: View {
    var body: some View {
        Rectangle()
            .fill(GAColors.border)
            .frame(height: 0.5)
    }
}
