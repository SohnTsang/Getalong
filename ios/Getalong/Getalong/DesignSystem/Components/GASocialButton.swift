import SwiftUI

/// Brand-tinted social sign-in button. All providers share height,
/// radius, padding, and font — only the icon and tint differ.
struct GASocialButton: View {
    enum Brand {
        case google, twitter

        var label: String {
            switch self {
            case .google:   return "Continue with Google"
            case .twitter:  return "Continue with X"
            }
        }
        /// SF Symbol fallback (no licensed brand assets shipped).
        var systemImage: String {
            switch self {
            case .google:   return "g.circle.fill"
            case .twitter:  return "xmark"
            }
        }
        /// Subtle brand tint for the icon only — keeps the row consistent.
        var iconTint: Color {
            switch self {
            case .google:   return Color(red: 0.93, green: 0.27, blue: 0.21)
            case .twitter:  return GAColors.textPrimary
            }
        }
    }

    let brand: Brand
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !isLoading && !isDisabled { action() } }) {
            HStack(spacing: GASpacing.md) {
                ZStack {
                    Circle()
                        .fill(brand.iconTint.opacity(0.10))
                        .frame(width: 28, height: 28)
                    Image(systemName: brand.systemImage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(brand.iconTint)
                }
                Text(brand.label)
                    .font(GATypography.button)
                    .foregroundStyle(GAColors.textPrimary)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView().tint(GAColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: GASpacing.controlHeight)
            .padding(.horizontal, GASpacing.lg)
            .background(GAColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                 style: .continuous)
                    .strokeBorder(GAColors.border, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
