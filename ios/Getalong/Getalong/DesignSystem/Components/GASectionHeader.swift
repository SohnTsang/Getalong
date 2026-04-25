import SwiftUI

/// Section header sitting above a card or a group of cards.
/// Title + optional subtitle on the left, optional action affordance on the right.
struct GASectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var actionSystemImage: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(GATypography.sectionTitle)
                    .tracking(0.8)
                    .foregroundStyle(GAColors.textTertiary)
                if let subtitle {
                    Text(subtitle)
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle).font(GATypography.footnote.weight(.semibold))
                        if let actionSystemImage {
                            Image(systemName: actionSystemImage)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(GAColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }
}
