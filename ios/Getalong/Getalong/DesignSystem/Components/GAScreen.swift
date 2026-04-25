import SwiftUI

/// A consistent screen container: warm background under safe area,
/// horizontal page margin, scroll, and a max content width on iPad.
struct GAScreen<Content: View>: View {
    enum Layout { case scroll, fixed }
    var layout: Layout = .scroll
    var maxWidth: CGFloat? = 560
    var horizontalPadding: CGFloat = GASpacing.screenHorizontal
    var topPadding: CGFloat = GASpacing.lg
    var bottomPadding: CGFloat = GASpacing.xxl
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            GAColors.background.ignoresSafeArea()

            Group {
                switch layout {
                case .scroll:
                    ScrollView {
                        body(of: content())
                    }
                case .fixed:
                    body(of: content())
                }
            }
        }
    }

    @ViewBuilder
    private func body<C: View>(of inner: C) -> some View {
        VStack(spacing: GASpacing.sectionGap) { inner }
            .frame(maxWidth: maxWidth ?? .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
    }
}
