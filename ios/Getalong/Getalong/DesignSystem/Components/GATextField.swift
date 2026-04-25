import SwiftUI

struct GATextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var systemImage: String? = nil
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text(title)
                .font(GATypography.caption)
                .foregroundStyle(GAColors.textSecondary)

            HStack(spacing: GASpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(GAColors.textTertiary)
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
            }
            .padding(.horizontal, GASpacing.lg)
            .frame(height: 48)
            .background(GAColors.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.md, style: .continuous)
                    .stroke(errorMessage == nil ? GAColors.border : GAColors.danger,
                            lineWidth: 1)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.danger)
            }
        }
    }
}
