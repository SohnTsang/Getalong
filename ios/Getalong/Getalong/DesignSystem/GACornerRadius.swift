import CoreGraphics

/// Corner radius tokens. Avoid arbitrary values in views.
enum GACornerRadius {
    static let small:  CGFloat = 8
    static let medium: CGFloat = 14
    static let large:  CGFloat = 20
    static let xlarge: CGFloat = 28
    static let pill:   CGFloat = 999

    // Backwards-compat aliases (previous code used `xs/sm/md/lg/xl`).
    static let xs = small
    static let sm = small + 2
    static let md = medium
    static let lg = large
    static let xl = xlarge
}
