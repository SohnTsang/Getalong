import SwiftUI

/// A looping countdown ring used in the auth hero to demonstrate the
/// 15-second live invite mechanic. Animates from `total` → 0, pauses for
/// a beat, then loops.
///
/// Visually:
/// * Outer track in `border`.
/// * Animated arc in `accent`, draws shorter as time elapses.
/// * Centered seconds digit in monospaced rounded.
/// * Subtle pulse expands once per cycle to suggest "live".
struct PulsingCountdownRing: View {
    var total: Double = 15
    var size: CGFloat = 64
    var lineWidth: CGFloat = 4

    @State private var elapsed: Double = 0
    @State private var pulse: Bool = false
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var remaining: Double { max(0, total - elapsed) }
    private var progress: Double { max(0, min(1, remaining / total)) }
    private var seconds: Int { max(0, Int(ceil(remaining))) }

    var body: some View {
        ZStack {
            // Outer pulse — barely visible, gives life
            Circle()
                .stroke(GAColors.accent.opacity(pulse ? 0 : 0.18), lineWidth: 1.5)
                .scaleEffect(pulse ? 1.18 : 1.0)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false),
                           value: pulse)

            // Track
            Circle()
                .stroke(GAColors.border, lineWidth: lineWidth)

            // Accent arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(GAColors.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(seconds)")
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GAColors.textPrimary)
        }
        .frame(width: size, height: size)
        .onAppear {
            pulse = true
        }
        .onReceive(timer) { _ in
            elapsed += 0.05
            // Pause for a beat at zero, then loop.
            if elapsed >= total + 0.8 { elapsed = 0 }
        }
        .accessibilityHidden(true)
    }
}
