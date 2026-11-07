import AppKit
import Dust3DEditorModel
import SwiftUI

/// The inactive drawing pane consumes only the click that activates it.
struct CanvasProfileActivationSurface: NSViewRepresentable {
    let activate: (CanvasProfileFocusRequest) -> Void

    func makeNSView(context: Context) -> CanvasProfileActivationView { CanvasProfileActivationView() }

    func updateNSView(_ view: CanvasProfileActivationView, context: Context) {
        view.activate = activate
    }

    static func dismantleNSView(_ view: CanvasProfileActivationView, coordinator: ()) {
        view.cancelPress()
        view.activate = { _ in }
    }
}

final class CanvasProfileActivationView: NSView {
    var activate: (CanvasProfileFocusRequest) -> Void = { _ in }
    private var press = CanvasProfileActivationPress()
    private var pendingActivation: (request: CanvasProfileFocusRequest, invoke: (CanvasProfileFocusRequest) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let modifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]
        let plain = event.buttonNumber == 0 && event.modifierFlags.intersection(modifiers).isEmpty
        cancelPress()
        guard plain, event.clickCount == 1, let window, window.isKeyWindow else { return }
        press.begin(at: point(event), clickCount: event.clickCount, isPlainPrimary: plain)
        // Keep the original lease and responder baseline if SwiftUI updates during the press.
        pendingActivation = (CanvasProfileFocusRequest(window: window), activate)
    }

    override func mouseDragged(with event: NSEvent) {
        press.move(to: point(event))
    }

    override func mouseUp(with event: NSEvent) {
        let location = point(event)
        let inside = bounds.contains(CGPoint(x: location.x, y: location.y))
        defer { cancelPress() }
        guard press.finish(at: location, isInside: inside), let pendingActivation, let window, window.isKeyWindow
        else { return }
        pendingActivation.invoke(pendingActivation.request)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelPress() }
        super.viewWillMove(toWindow: newWindow)
    }

    func cancelPress() {
        press.cancel()
        pendingActivation = nil
    }

    private func point(_ event: NSEvent) -> CanvasPoint {
        let location = convert(event.locationInWindow, from: nil)
        return CanvasPoint(x: location.x, y: location.y)
    }
}

/// A mouse-driven profile change may claim focus once in the originating window.
@MainActor
final class CanvasProfileFocusRequest {
    private weak var window: NSWindow?
    private weak var previousResponder: NSResponder?
    private let previousWasCanvas: Bool
    private(set) var isPending = true

    init(window: NSWindow) {
        self.window = window
        let previous = window.firstResponder
        previousResponder = previous
        previousWasCanvas = previous is CanvasPointerView || previous is NodePointerView
    }

    func claim(for view: CanvasPointerView, ownsProfile: Bool) {
        guard isPending, view.superview != nil, let attachedWindow = view.window else { return }
        isPending = false
        guard ownsProfile, attachedWindow === window, attachedWindow.isKeyWindow,
            attachedWindow.attachedSheet == nil, attachedWindow.sheetParent == nil, NSApp.modalWindow == nil
        else { return }
        let current = attachedWindow.firstResponder
        let detachedCanvas = previousWasCanvas && (previousResponder as? NSView)?.window == nil
        guard current === previousResponder || (detachedCanvas && current === attachedWindow) else { return }
        attachedWindow.makeFirstResponder(view)
    }
}
