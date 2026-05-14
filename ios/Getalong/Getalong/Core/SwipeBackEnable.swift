import UIKit
import ObjectiveC

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
///
/// Implementation note: we used to declare
/// `extension UINavigationController: UIGestureRecognizerDelegate`,
/// but that's a retroactive conformance — the Swift compiler warns
/// because if a future UIKit version adopts the protocol on
/// UINavigationController itself, both conformances would conflict.
/// The clean fix is a dedicated delegate object held on the nav
/// controller via an Obj-C associated object; the extension only
/// installs the gesture and wires the delegate.
extension UINavigationController {
    override open func viewDidLoad() {
        super.viewDidLoad()
        installSwipeFromAnywhereIfNeeded()
    }

    private func installSwipeFromAnywhereIfNeeded() {
        guard let edgePop = interactivePopGestureRecognizer else { return }
        let delegate = swipeBackDelegate
        edgePop.delegate = delegate
        // Don't reinstall on every push.
        if view.gestureRecognizers?.contains(where: { $0 is FullPanRecognizer }) == true {
            return
        }
        let pan = FullPanRecognizer()
        pan.delegate = delegate
        // Reuse the system recognizer's action handlers — that's
        // what drives the interactive pop animation.
        if let targets = edgePop.value(forKey: "targets") {
            pan.setValue(targets, forKey: "targets")
        }
        view.addGestureRecognizer(pan)
    }

    /// Lazily-allocated delegate, retained on the nav controller via
    /// an Obj-C associated object so it lives exactly as long as the
    /// nav controller does. Same instance is reused across the system
    /// edge recognizer and our full-screen pan.
    private var swipeBackDelegate: SwipeBackGestureDelegate {
        if let existing = objc_getAssociatedObject(self, &swipeBackDelegateKey)
            as? SwipeBackGestureDelegate {
            return existing
        }
        let d = SwipeBackGestureDelegate(navigationController: self)
        objc_setAssociatedObject(
            self,
            &swipeBackDelegateKey,
            d,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return d
    }
}

/// Stable pointer identity for the associated-object key. Its value
/// is never read or mutated — only its address is used by
/// `objc_get/setAssociatedObject`. File-scope `private var` keeps it
/// out of any other translation unit's namespace.
private var swipeBackDelegateKey: UInt8 = 0

/// Real `UIGestureRecognizerDelegate` for the swipe-back gestures.
/// Owns a weak ref back to the nav controller so it can read
/// `viewControllers` / `transitionCoordinator` at recognition time
/// without retaining the controller.
private final class SwipeBackGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        super.init()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        // Nothing to pop to → don't engage either gesture.
        guard nav.viewControllers.count > 1 else { return false }
        // Mid-push animations bork interactive transitions; ignore.
        if let coordinator = nav.transitionCoordinator, coordinator.isAnimated {
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

    func gestureRecognizer(
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
