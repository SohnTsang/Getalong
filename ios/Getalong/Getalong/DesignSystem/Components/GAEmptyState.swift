import SwiftUI

struct GAEmptyState: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "sparkles"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: GASpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(GAColors.textTertiary)
                .padding(.bottom, GASpacing.xs)

            Text(title)
                .font(GATypography.headline)
                .foregroundStyle(GAColors.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                GAButton(title: actionTitle, kind: .secondary, size: .compact, action: action)
                    .padding(.top, GASpacing.sm)
            }
        }
        .padding(GASpacing.xl)
        .frame(maxWidth: .infinity)
    }
}
