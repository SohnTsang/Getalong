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
    /// When true, short content sits vertically centred in the available
    /// height; long content still scrolls. Useful for onboarding-style
    /// screens with one focused card.
    var centerVertically: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            GAColors.background.ignoresSafeArea()

            Group {
                switch layout {
                case .scroll:
                    if centerVertically {
                        GeometryReader { proxy in
                            ScrollView {
                                contentBody
                                    .frame(maxWidth: .infinity,
                                           minHeight: proxy.size.height,
                                           alignment: .center)
                            }
                        }
                    } else {
                        ScrollView { contentBody }
                    }
                case .fixed:
                    contentBody
                }
            }
        }
    }

    private var contentBody: some View {
        VStack(spacing: GASpacing.sectionGap) { content() }
            .frame(maxWidth: maxWidth ?? .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
    }
}
