import SwiftUI

/// The preview sheet shown after the user picks media. Lets the user
/// confirm send, cancel, or retry on failure.
struct MediaComposerSheet: View {
    @ObservedObject var controller: MediaUploadController
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: GASpacing.lg) {
            header
            preview
            stateRow
            privacyNote
            Spacer(minLength: 0)
            actions
        }
        .padding(GASpacing.lg)
        .background(GAColors.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("media.composer.title")
                .font(GATypography.title)
                .foregroundStyle(GAColors.textPrimary)
            Spacer()
            if !isBusy {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GAColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(GAColors.surfaceRaised, in: Circle())
                }
                .accessibilityLabel(String(localized: "common.cancel"))
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GACornerRadius.large, style: .continuous)
                .fill(GAColors.surfaceRaised)

            if let img = controller.thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large, style: .continuous))
            } else {
                placeholder
            }

            if controller.state == .preparing {
                ProgressView()
                    .controlSize(.large)
            }

            VStack {
                HStack {
                    Spacer()
                    Label(viewOnceLabel, systemImage: "eye")
                        .font(GATypography.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(GASpacing.sm)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.large, style: .continuous)
                .strokeBorder(GAColors.border, lineWidth: 0.75)
        )
    }

    private var placeholder: some View {
        VStack(spacing: GASpacing.sm) {
            Image(systemName: iconForKind)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(GAColors.textTertiary)
            Text("media.preparing")
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textTertiary)
        }
    }

    private var stateRow: some View {
        Group {
            switch controller.state {
            case .preparing, .uploading, .sending:
                HStack(spacing: GASpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(controller.stateLabel)
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textSecondary)
                }
            case .failedBeforeUpload(let m), .failedAfterUpload(let m, _):
                HStack(spacing: GASpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(GAColors.danger)
                    Text(m)
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.danger)
                        .multilineTextAlignment(.leading)
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var privacyNote: some View {
        Text("media.privacy.note")
            .font(GATypography.caption)
            .foregroundStyle(GAColors.textTertiary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: GASpacing.sm) {
            switch controller.state {
            case .readyPreview:
                GAButton(title: String(localized: "common.send"),
                         kind: .primary, action: onConfirm)
            case .uploading, .sending, .preparing:
                GAButton(title: controller.stateLabel,
                         kind: .primary, isLoading: true, isDisabled: true) {}
                GAButton(title: String(localized: "media.cancelUpload"),
                         kind: .ghost, action: onClose)
            case .failedBeforeUpload, .failedAfterUpload:
                GAButton(title: String(localized: "media.retry"),
                         kind: .primary) {
                    controller.retry(onSuccess: { _ in })
                }
                GAButton(title: String(localized: "media.remove"),
                         kind: .ghost, action: onClose)
            case .idle:
                EmptyView()
            }
        }
    }

    // MARK: - Helpers

    private var isBusy: Bool {
        switch controller.state {
        case .preparing, .uploading, .sending: return true
        default: return false
        }
    }

    private var iconForKind: String {
        switch controller.prepared?.kind {
        case .video: return "video"
        case .gif:   return "sparkles.tv"
        case .image: return "photo"
        default:     return "photo"
        }
    }

    private var viewOnceLabel: String {
        switch controller.prepared?.kind {
        case .video: return String(localized: "media.viewOnce.video")
        case .gif:   return String(localized: "media.viewOnce.gif")
        case .image: return String(localized: "media.viewOnce.photo")
        default:     return String(localized: "media.viewOnce.label")
        }
    }
}
