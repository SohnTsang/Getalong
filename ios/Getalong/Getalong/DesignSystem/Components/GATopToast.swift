import SwiftUI

/// Top-of-content toast surface used for transient feedback that does
/// NOT belong inline under a card. Single component covers the three
/// semantic kinds the app surfaces:
///
///   * `.success` — checkmark, success tint, 2.4 s auto-dismiss
///   * `.warning` — triangle, warning tint, 3.2 s auto-dismiss
///   * `.error`   — octagon-x, danger tint, 3.2 s auto-dismiss
///
/// All three share the same shell: `surfaceRaised` capsule with a soft
/// shadow, thin border, drag-up dismiss (28-pt threshold), and a
/// `.task(id: message)` auto-dismiss timer that restarts only when the
/// message actually changes.
///
/// `ChatErrorToast` (private to `ChatRoomView`) intentionally lives
/// outside this component because its body wraps `GAErrorBanner` for
/// the inline-X dismiss affordance — useful in a chat where the user
/// may be mid-typing. The shell duplication is acknowledged and
/// accepted there; if the inline-X requirement is dropped later, that
/// callsite can be migrated to `GATopToast(kind: .error, ...)`.
struct GATopToast: View {
    enum Kind {
        case success
        case warning
        case error

        var systemImageName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return GAColors.success
            case .warning: return GAColors.warning
            case .error:   return GAColors.danger
            }
        }

        /// Auto-dismiss delay. Success is short ("got it");
        /// warning / error sit longer so the user has time to read.
        var dismissAfter: UInt64 {
            switch self {
            case .success:            return 2_400_000_000
            case .warning, .error:    return 3_200_000_000
            }
        }
    }

    let kind: Kind
    let message: String
    let onDismiss: () -> Void

    @State private var dragY: CGFloat = 0

    var body: some View {
        HStack(spacing: GASpacing.sm) {
            Image(systemName: kind.systemImageName)
                .foregroundStyle(kind.tint)
                .font(.system(size: 18, weight: .regular))
            Text(message)
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GASpacing.md)
        .padding(.vertical, GASpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: GACornerRadius.medium,
                             style: .continuous)
                .fill(GAColors.surfaceRaised)
                .shadow(color: Color.black.opacity(0.10),
                        radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.medium,
                             style: .continuous)
                .strokeBorder(GAColors.border, lineWidth: 0.5)
        )
        .offset(y: min(dragY, 0))
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    dragY = min(v.translation.height, 0)
                }
                .onEnded { v in
                    if v.translation.height < -28 {
                        onDismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            dragY = 0
                        }
                    }
                }
        )
        .task(id: message) {
            try? await Task.sleep(nanoseconds: kind.dismissAfter)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
