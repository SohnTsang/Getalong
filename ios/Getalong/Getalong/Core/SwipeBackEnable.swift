import UIKit

/// Re-enables the interactive-pop gesture (left-edge swipe to go back)
/// on screens that hide the back button or navigation bar entirely.
/// SwiftUI's NavigationStack normally drops the gesture along with
/// the bar, which breaks an interaction users expect from every other
/// iOS app. We restore it by setting the recognizer's delegate to a
/// permissive stub that always says "yes, begin".
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only allow when there's actually something to pop to.
        viewControllers.count > 1
    }
}
