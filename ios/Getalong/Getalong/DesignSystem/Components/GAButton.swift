import SwiftUI

enum GAButtonStyleKind {
    case primary
    case secondary
    case ghost
    case destructive
    case social        // SSO row buttons
    case compact       // small inline actions
}

enum GAButtonSize {
    case regular, compact

    var height: CGFloat {
        switch self {
        case .regular: return GASpacing.controlHeight
        case .compact: return GASpacing.compactControlHeight
        }
    }
    var horizontalPadding: CGFloat {
        switch self {
        case .regular: return GASpacing.lg
        case .compact: return GASpacing.md
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
    var fillsWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if !isLoading && !isDisabled { action() } }) {
            label
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size.height)
                .padding(.horizontal, size.horizontalPadding)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                     style: .continuous)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .opacity(isDisabled ? 0.55 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(GAPressStyle())
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var label: some View {
        if isLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(foreground)
        } else {
            HStack(spacing: GASpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title).font(GATypography.button)
            }
        }
    }

    // MARK: Style mapping

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:     GAColors.accent
        case .secondary:   GAColors.surfaceRaised
        case .ghost:       Color.clear
        case .destructive: GAColors.danger
        case .social:      GAColors.surface
        case .compact:     GAColors.surfaceRaised
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary:     return GAColors.accentText
        case .destructive: return GAColors.accentText
        case .secondary, .ghost, .compact, .social: return GAColors.textPrimary
        }
    }

    private var borderColor: Color {
        switch kind {
        case .ghost:  return GAColors.border
        case .social: return GAColors.border
        default:      return Color.clear
        }
    }
    private var borderWidth: CGFloat {
        switch kind {
        case .ghost, .social: return 1
        default:              return 0
        }
    }
}

/// Subtle press animation. Calmer than the default 0.5 opacity blink.
private struct GAPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
