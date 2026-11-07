import Dust3DEditorModel

/// Presentation invalidation is distinct from a silent SwiftUI lifecycle reset.
/// Return notifications as values so native mutation ends before callbacks run.
struct CanvasPointerActivity {
    var hasMarquee = false
    var hasHover = false

    struct Cancellation {
        let clearsMarquee: Bool
        let clearsHover: Bool

        @MainActor func notify(
            rectangle: (CanvasSelectionRectangle?) -> Void, hover: (CanvasPoint?) -> Void
        ) {
            if clearsMarquee { rectangle(nil) }
            if clearsHover { hover(nil) }
        }
    }

    mutating func clear() -> Cancellation {
        let cancellation = Cancellation(clearsMarquee: hasMarquee, clearsHover: hasHover)
        self = Self()
        return cancellation
    }

    mutating func finishMarquee() -> Cancellation {
        let cancellation = Cancellation(clearsMarquee: hasMarquee, clearsHover: false)
        hasMarquee = false
        return cancellation
    }
}
