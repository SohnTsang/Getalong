import SwiftUI

struct GAErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: GASpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GAColors.danger)

            VStack(alignment: .leading, spacing: GASpacing.xs) {
                Text(message)
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textPrimary)

                if onRetry != nil || onDismiss != nil {
                    HStack(spacing: GASpacing.lg) {
                        if let onRetry {
                            Button("Retry", action: onRetry)
                                .font(GATypography.caption)
                                .foregroundStyle(GAColors.accent)
                        }
                        if let onDismiss {
                            Button("Dismiss", action: onDismiss)
                                .font(GATypography.caption)
                                .foregroundStyle(GAColors.textSecondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(GASpacing.md)
        .background(GAColors.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous)
                .stroke(GAColors.danger.opacity(0.3), lineWidth: 1)
        )
    }
}
