import AppKit

/// Routes explicit camera gestures before the background or node graph responder claims them.
class CanvasCameraPointerView: NSView {
    var beginPreviewDrag: CanvasPreviewDrag.Begin?
    var canBeginPreviewDrag: Bool { false }
    private var previewDrag = CanvasPreviewDrag()
    var isPreviewDragging: Bool { previewDrag.isActive }

    func routePreviewPress(_ event: NSEvent) -> Bool {
        guard canBeginPreviewDrag, let beginPreviewDrag,
            CanvasPreviewDrag.accepts(button: event.buttonNumber, modifiers: event.modifierFlags)
        else { return false }
        // Transfer focus before reserving the viewport's camera so that
        // its first-responder loss cannot cancel the newly forwarded drag.
        let previousResponder = window?.firstResponder
        if let window, previousResponder !== self, !window.makeFirstResponder(self) { return false }
        let accepted = previewDrag.press(
            button: event.buttonNumber, modifiers: event.modifierFlags,
            location: event.locationInWindow, begin: beginPreviewDrag)
        if !accepted, let window, window.firstResponder === self, previousResponder !== self {
            window.makeFirstResponder(previousResponder)
        }
        return accepted
    }

    func routePreviewDrag(_ event: NSEvent) -> Bool {
        previewDrag.drag(
            button: event.buttonNumber, modifiers: event.modifierFlags, location: event.locationInWindow)
    }

    func routePreviewRelease(_ event: NSEvent) -> Bool {
        previewDrag.release(button: event.buttonNumber)
    }

    func cancelPreviewDrag() { previewDrag.cancel() }

    override func otherMouseDown(with event: NSEvent) {
        if !routePreviewPress(event) { super.otherMouseDown(with: event) }
    }

    override func otherMouseDragged(with event: NSEvent) {
        if !routePreviewDrag(event) { super.otherMouseDragged(with: event) }
    }

    override func otherMouseUp(with event: NSEvent) {
        if !routePreviewRelease(event) { super.otherMouseUp(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { cancelPreviewDrag() }
        return accepted
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelPreviewDrag() }
        super.viewWillMove(toWindow: newWindow)
    }
}
