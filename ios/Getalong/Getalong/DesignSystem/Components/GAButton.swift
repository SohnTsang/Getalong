import SwiftUI

enum GAButtonStyleKind {
    case primary
    case secondary
    case ghost
    case destructive
}

enum GAButtonSize {
    case regular
    case compact

    var height: CGFloat {
        switch self {
        case .regular: return 52
        case .compact: return 40
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular: return GASpacing.xl
        case .compact: return GASpacing.lg
        }
    }
}

struct GAButton: View {
    let title: String
    var systemImage: String? = nil
    var kind: GAButtonStyleKind = .primary
    var size: GAButtonSize = .regular
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !isLoading && !isDisabled { action() } }) {
            HStack(spacing: GASpacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foreground)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                        .font(GATypography.button)
                }
            }
            .frame(maxWidth: .infinity, minHeight: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous))
            .overlay(border)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
    }

    // MARK: Style mapping

    private var background: some View {
        switch kind {
        case .primary:     return AnyView(GAColors.accent)
        case .secondary:   return AnyView(GAColors.surfaceMuted)
        case .ghost:       return AnyView(Color.clear)
        case .destructive: return AnyView(GAColors.danger)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive: return GAColors.textOnAccent
        case .secondary, .ghost:     return GAColors.textPrimary
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .ghost:
            RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous)
                .stroke(GAColors.border, lineWidth: 1)
        default:
            EmptyView()
        }
    }
}
