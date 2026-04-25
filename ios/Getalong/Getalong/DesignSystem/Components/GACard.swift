import SwiftUI

/// A reusable card container with semantic kinds.
struct GACard<Content: View>: View {
    var kind: GACardKind = .standard
    var padding: CGFloat = GASpacing.cardPadding
    var radius:  CGFloat = GACornerRadius.large
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .gaCard(kind, padding: padding, radius: radius)
    }
}
