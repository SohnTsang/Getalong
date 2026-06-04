import Foundation

extension Error {
    /// True when this error represents a cooperative task cancellation or
    /// an in-flight URLSession cancellation — neither is a real
    /// user-facing failure. Swift concurrency throws these whenever the
    /// `Task` surrounding a SwiftUI `.task` / `.refreshable` closure is
    /// torn down: view disappear, tab switch, a refresh racing the
    /// initial load, or one request superseding another.
    ///
    /// Callers should treat a cancellation as a no-op: do NOT show an
    /// error banner/toast/card, do NOT clear good cached state, and do
    /// NOT start refresh cooldowns.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let ns = self as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
            return true
        }
        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }
}
