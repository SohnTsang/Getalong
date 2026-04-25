import SwiftUI

/// Pill-shaped chip used for topics, filters, tags.
struct GAChip: View {
    let label: String
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        let content = Text(label)
            .font(GATypography.caption)
            .padding(.horizontal, GASpacing.md)
            .padding(.vertical, GASpacing.sm)
            .background(isSelected ? GAColors.accentSoft : GAColors.surfaceMuted)
            .foregroundStyle(isSelected ? GAColors.accent : GAColors.textPrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? GAColors.accent : GAColors.border,
                            lineWidth: 1)
            )

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}
