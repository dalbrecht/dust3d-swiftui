import AppKit
import Dust3DEditorModel
import SwiftUI

/// A narrow AppKit input boundary gives every pointer activation its own identity.
struct NodePointerSurface: NSViewRepresentable {
    let enabled: Bool
    let canDrag: Bool
    let begin: (UUID) -> Void
    let update: (UUID, CanvasPoint) -> Void
    let finish: (UUID, CanvasPoint) -> Void
    let cancel: (UUID) -> Void
    let select: () -> Void
    let toggle: () -> Void

    func makeNSView(context: Context) -> NodePointerView { NodePointerView() }
    func updateNSView(_ view: NodePointerView, context: Context) {
        view.enabled = enabled
        view.canDrag = canDrag
        view.begin = begin
        view.update = update
        view.finish = finish
        view.cancel = cancel
        view.select = select
        view.toggle = toggle
    }
}

final class NodePointerView: NSView {
    var enabled = false
    var canDrag = false
    var begin: (UUID) -> Void = { _ in }
    var update: (UUID, CanvasPoint) -> Void = { _, _ in }
    var finish: (UUID, CanvasPoint) -> Void = { _, _ in }
    var cancel: (UUID) -> Void = { _ in }
    var select: () -> Void = {}
    var toggle: () -> Void = {}
    private var activation: (token: UUID, origin: NSPoint, isDragging: Bool, isCommand: Bool)?
    private weak var previousResponder: NSResponder?

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard enabled, bounds.contains(local) else { return nil }
        let dx = local.x - bounds.midX
        let dy = local.y - bounds.midY
        return dx * dx + dy * dy <= 18 * 18 ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        if activation != nil { cancelActivation() }
        let token = UUID()
        activation = (token, event.locationInWindow, false, event.modifierFlags.contains(.command))
        if canDrag { begin(token) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = activation else { return }
        guard enabled, canDrag else {
            cancelActivation()
            return
        }
        let translation = displacement(from: current.origin, to: event.locationInWindow)
        guard current.isDragging || hypot(translation.x, translation.y) >= 3 else { return }
        if !current.isDragging, let window {
            previousResponder = window.firstResponder
            guard window.makeFirstResponder(self) else {
                cancelActivation()
                return
            }
        }
        current.isDragging = true
        activation = current
        update(current.token, translation)
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = activation else { return }
        activation = nil
        restoreResponder()
        guard enabled else {
            cancel(current.token)
            return
        }
        if current.isDragging && canDrag {
            finish(current.token, displacement(from: current.origin, to: event.locationInWindow))
        } else {
            cancel(current.token)
            if current.isCommand { toggle() } else { select() }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        }
        if newWindow !== window { cancelActivation() }
        super.viewWillMove(toWindow: newWindow)
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification, object: newWindow)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53, activation != nil else {
            super.keyDown(with: event)
            return
        }
        cancelActivation()
    }

    @objc private func windowResigned() { cancelActivation() }

    private func cancelActivation() {
        guard let current = activation else { return }
        activation = nil
        restoreResponder()
        cancel(current.token)
    }

    private func restoreResponder() {
        defer { previousResponder = nil }
        guard let window, window.firstResponder === self else { return }
        if let previous = previousResponder as? NSView, previous.window !== window { return }
        window.makeFirstResponder(previousResponder)
    }

    private func displacement(from origin: NSPoint, to point: NSPoint) -> CanvasPoint {
        .init(x: point.x - origin.x, y: origin.y - point.y)
    }
}
