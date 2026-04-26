import SwiftUI
import PhotosUI

struct ChatInputBar: View {
    @Binding var text: String
    var isSending: Bool
    var canSend: Bool
    var canAttachMedia: Bool
    let onSend: () -> Void
    let onAttachPicked: (MediaUploadController.PickerSource) -> Void

    @FocusState private var isFocused: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPicked = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(GAColors.border).frame(height: 0.5)
            HStack(alignment: .bottom, spacing: GASpacing.sm) {
                attachButton

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("chat.input.placeholder")
                            .font(GATypography.body)
                            .foregroundStyle(GAColors.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $text, axis: .vertical)
                        .font(GATypography.body)
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($isFocused)
                        .textInputAutocapitalization(.sentences)
                }
                .background(GAColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GACornerRadius.large,
                                     style: .continuous)
                        .strokeBorder(GAColors.border, lineWidth: 1)
                )

                Button(action: { if canSend { onSend() } }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GAColors.accentText)
                        .frame(width: 38, height: 38)
                        .background(canSend ? GAColors.accent : GAColors.surfaceRaised)
                        .clipShape(Circle())
                        .opacity(isSending ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
                .accessibilityLabel(String(localized: "chat.input.send"))
            }
            .padding(.horizontal, GASpacing.lg)
            .padding(.vertical, GASpacing.sm)
            .background(GAColors.background)
        }
        .onChange(of: pickerItem) { newValue in
            guard let newValue else { return }
            isLoadingPicked = true
            Task {
                let source = await MediaPickerLoader.resolve(newValue)
                await MainActor.run {
                    isLoadingPicked = false
                    pickerItem = nil
                    if let source { onAttachPicked(source) }
                }
            }
        }
    }

    private var attachButton: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) {
            ZStack {
                Circle().fill(GAColors.surfaceRaised).frame(width: 38, height: 38)
                if isLoadingPicked {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GAColors.textPrimary)
                }
            }
        }
        .disabled(!canAttachMedia || isLoadingPicked)
        .accessibilityLabel(String(localized: "media.button.attach"))
    }
}
