import SwiftUI

struct GALoadingView: View {
    var label: String? = nil

    var body: some View {
        VStack(spacing: GASpacing.md) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(GAColors.accent)
            if let label {
                Text(label)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GAColors.background.ignoresSafeArea())
    }
}
