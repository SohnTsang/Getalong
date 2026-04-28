import UIKit

/// Re-enables and *expands* the interactive-pop gesture so that:
///
///   * the left-edge swipe still works on screens that hide the
///     navigation bar (SwiftUI normally drops it),
///   * a swipe started anywhere on the screen drives the same
///     interactive pop transition — partial swipe shows a preview of
///     the previous view; release past ~1/3 of the screen pops, else
///     snaps back. This matches WhatsApp / Telegram / Messenger.
///
/// We piggy-back on the system's `interactivePopGestureRecognizer`
/// rather than rolling our own transition: a fresh `UIPanGestureRecognizer`
/// installed on the nav controller's view shares the same private
/// `targets` as the edge recognizer, which forwards pan events into
/// `_UINavigationInteractiveTransition`. The animation, threshold, and
/// release behaviour all come for free from UIKit — we only have to
/// avoid firing during vertical scrolls.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        installSwipeFromAnywhereIfNeeded()
    }

    private func installSwipeFromAnywhereIfNeeded() {
        guard let edgePop = interactivePopGestureRecognizer else { return }
        edgePop.delegate = self
        // Don't reinstall on every push.
        if view.gestureRecognizers?.contains(where: { $0 is FullPanRecognizer }) == true {
            return
        }
        let pan = FullPanRecognizer()
        pan.delegate = self
        // Reuse the system recognizer's action handlers — that's
        // what drives the interactive pop animation.
        if let targets = edgePop.value(forKey: "targets") {
            pan.setValue(targets, forKey: "targets")
        }
        view.addGestureRecognizer(pan)
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Nothing to pop to → don't engage either gesture.
        guard viewControllers.count > 1 else { return false }
        // Mid-push animations bork interactive transitions; ignore.
        if let coordinator = transitionCoordinator, coordinator.isAnimated {
            return false
        }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            // Only begin when the user is clearly dragging right —
            // velocity check is reliable at gesture start (translation
            // is still 0). The horizontal-dominates rule keeps the
            // chat scroll's vertical drags from flipping us into a
            // pop.
            let v = pan.velocity(in: pan.view)
            return v.x > 0 && abs(v.x) > abs(v.y) * 1.2
        }
        return true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // The system edge recognizer + our full-screen pan must not
        // race each other; otherwise both fire and the transition
        // jitters. Our pan is always installed alongside the edge
        // one, so explicitly disallow simultaneous recognition.
        false
    }
}

/// Marker subclass so we can dedupe installations across nav stacks.
private final class FullPanRecognizer: UIPanGestureRecognizer {}
