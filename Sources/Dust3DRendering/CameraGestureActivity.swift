/// Shared activity survives AppKit reinterpreting a pinch as rotation.
struct CameraGestureActivity {
    enum Phase { case mayBegin, began, changed, stationary, ended, cancelled, none }
    private(set) var isActive = false

    mutating func update(_ phase: Phase) {
        switch phase {
        case .mayBegin, .began, .changed, .stationary: isActive = true
        case .ended, .cancelled, .none: isActive = false
        }
    }
    mutating func cancel() { isActive = false }
}
