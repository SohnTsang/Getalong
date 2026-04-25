import CoreGraphics

/// 4-pt spacing scale plus screen-level constants.
enum GASpacing {
    static let xxs:  CGFloat = 2
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 20
    static let xxl:  CGFloat = 28
    static let xxxl: CGFloat = 40

    /// Standard horizontal page margin. Matches Apple's HIG intent.
    static let screenHorizontal: CGFloat = 20

    /// Internal padding for a card. Slightly tighter than screen margin.
    static let cardPadding: CGFloat = 18

    /// Vertical rhythm between major sections inside a screen.
    static let sectionGap: CGFloat = 22

    /// Standard control height — buttons, segmented pickers, text fields.
    static let controlHeight: CGFloat = 52
    static let compactControlHeight: CGFloat = 40
}
