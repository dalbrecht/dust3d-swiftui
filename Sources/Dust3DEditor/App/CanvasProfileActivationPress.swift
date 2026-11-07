import Dust3DEditorModel
import Foundation

/// Recognizes a click that switches editing profiles without forwarding an edit.
struct CanvasProfileActivationPress {
    private var start: CanvasPoint?

    mutating func begin(at point: CanvasPoint, clickCount: Int, isPlainPrimary: Bool) {
        start = isPlainPrimary && clickCount == 1 && point.x.isFinite && point.y.isFinite ? point : nil
    }

    mutating func move(to point: CanvasPoint) {
        guard let start else { return }
        if !point.x.isFinite || !point.y.isFinite || hypot(point.x - start.x, point.y - start.y) >= 3 {
            cancel()
        }
    }

    mutating func finish(at point: CanvasPoint, isInside: Bool) -> Bool {
        move(to: point)
        defer { cancel() }
        return isInside && start != nil
    }

    mutating func cancel() {
        start = nil
    }
}
