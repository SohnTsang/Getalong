import SwiftUI

struct GAEmptyState: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "sparkles"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: GASpacing.md) {
            ZStack {
                Circle()
                    .fill(GAColors.surfaceRaised)
                    .frame(width: 64, height: 64)
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(GAColors.textSecondary)
            }
            .padding(.bottom, GASpacing.xs)

            Text(title)
                .font(GATypography.title)
                .foregroundStyle(GAColors.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                GAButton(title: actionTitle,
                         kind: .secondary,
                         size: .compact,
                         fillsWidth: false,
                         action: action)
                    .padding(.top, GASpacing.sm)
            }
        }
        .padding(.vertical, GASpacing.xxl)
        .padding(.horizontal, GASpacing.lg)
        .frame(maxWidth: .infinity)
    }
}
