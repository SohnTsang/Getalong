import SwiftUI

enum GABannerKind {
    case info, success, warning, error
}

struct GAErrorBanner: View {
    let message: String
    var kind: GABannerKind = .error
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: GASpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: GASpacing.xs) {
                Text(message)
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textPrimary)

                if onRetry != nil || onDismiss != nil {
                    HStack(spacing: GASpacing.lg) {
                        if let onRetry {
                            Button("Retry", action: onRetry)
                                .font(GATypography.footnote.weight(.semibold))
                                .foregroundStyle(GAColors.accent)
                        }
                        if let onDismiss {
                            Button("Dismiss", action: onDismiss)
                                .font(GATypography.footnote)
                                .foregroundStyle(GAColors.textSecondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(GASpacing.md)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.medium,
                             style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        )
    }

    private var tint: Color {
        switch kind {
        case .info:    return GAColors.secondary
        case .success: return GAColors.success
        case .warning: return GAColors.warning
        case .error:   return GAColors.danger
        }
    }
    private var icon: String {
        switch kind {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "exclamationmark.octagon.fill"
        }
    }
}
