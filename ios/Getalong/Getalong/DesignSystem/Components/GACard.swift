import SwiftUI

/// A reusable card container. Use for posts, invite previews, profile blocks.
struct GACard<Content: View>: View {
    var padding: CGFloat = GASpacing.lg
    var radius: CGFloat = GACornerRadius.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .gaCard(padding: padding, radius: radius)
    }
}
