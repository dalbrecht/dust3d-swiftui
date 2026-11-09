/// Shared activity survives AppKit reinterpreting a pinch as rotation.
struct CameraGestureActivity {
    enum Phase { case mayBegin, began, changed, stationary, ended, cancelled, none }
    private(set) var isActive = false
    private var discardsContinuation = false

    mutating func admits(_ phase: Phase) -> Bool {
        switch phase {
        case .mayBegin, .began, .none:
            discardsContinuation = false
        case .changed, .stationary, .ended, .cancelled:
            break
        }
        return !discardsContinuation
    }

    mutating func update(_ phase: Phase) {
        switch phase {
        case .mayBegin, .began, .changed, .stationary: isActive = true
        case .ended, .cancelled, .none: isActive = false
        }
    }
    mutating func cancel() {
        if isActive { discardContinuation() }
    }

    mutating func discardContinuation() {
        discardsContinuation = true
        isActive = false
    }
}
