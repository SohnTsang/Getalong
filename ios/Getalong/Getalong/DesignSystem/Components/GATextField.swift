import SwiftUI

struct GATextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var systemImage: String? = nil
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var helperText: String? = nil
    var errorMessage: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text(title.uppercased())
                .font(GATypography.sectionTitle)
                .foregroundStyle(GAColors.textTertiary)
                .tracking(0.6)

            HStack(spacing: GASpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isFocused ? GAColors.textSecondary : GAColors.textTertiary)
                }
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(GATypography.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .focused($isFocused)
            }
            .padding(.horizontal, GASpacing.lg)
            .frame(height: GASpacing.controlHeight)
            .background(GAColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                 style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: errorMessage != nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.danger)
            } else if let helperText {
                Text(helperText)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textTertiary)
            }
        }
    }

    private var borderColor: Color {
        if errorMessage != nil { return GAColors.danger }
        if isFocused          { return GAColors.accent.opacity(0.7) }
        return GAColors.border
    }
    private var borderWidth: CGFloat { isFocused || errorMessage != nil ? 1.5 : 1 }
}
