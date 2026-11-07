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
    var add: () -> Void = {}
    var subtract: (() -> Void)? = nil
    var wheel: (CanvasWheelInput) -> Bool = { _ in false }
    var radiusKey: (Int) -> Bool = { _ in false }
    var doubleClick: (() -> Void)? = nil
    var precisionKey: ((CanvasPrecisionKeyInput) -> Bool)? = nil
    var isRectangular = false
    var clickCancel: ((UUID) -> Void)? = nil
    var beginShiftDrag: ((UUID) -> Void)? = nil
    var admitsPrimaryPress: ((Int) -> Bool)? = nil
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)? = nil
    var retainVisibilityFocus: ((CanvasProfileFocusRequest) -> Void)? = nil

    func makeNSView(context: Context) -> NodePointerView { NodePointerView() }
    static func dismantleNSView(_ view: NodePointerView, coordinator: ()) {
        view.cancelActivation(deferred: true, restoringFocus: false)
        view.enabled = false
        view.precisionKey = nil
        view.switchProfile = nil
        view.retainVisibilityFocus = nil
    }
    func updateNSView(_ view: NodePointerView, context: Context) {
        if !enabled { view.cancelActivation(deferred: true, restoringFocus: false) }
        view.enabled = enabled
        view.canDrag = canDrag
        view.begin = begin
        view.beginShiftDrag = beginShiftDrag
        view.update = update
        view.finish = finish
        view.cancel = cancel
        view.select = select
        view.toggle = toggle
        view.add = add
        view.subtract = subtract
        view.wheel = wheel
        view.radiusKey = radiusKey
        view.doubleClick = doubleClick
        view.precisionKey = precisionKey
        view.isRectangular = isRectangular
        view.clickCancel = clickCancel
        view.admitsPrimaryPress = admitsPrimaryPress
        view.switchProfile = switchProfile
        view.retainVisibilityFocus = retainVisibilityFocus
    }
}

final class NodePointerView: NSView {
    var enabled = false
    var canDrag = false
    var begin: (UUID) -> Void = { _ in }
    var beginShiftDrag: ((UUID) -> Void)?
    var update: (UUID, CanvasPoint) -> Void = { _, _ in }
    var finish: (UUID, CanvasPoint) -> Void = { _, _ in }
    var cancel: (UUID) -> Void = { _ in }
    var select: () -> Void = {}
    var toggle: () -> Void = {}
    var add: () -> Void = {}
    var subtract: (() -> Void)?
    var wheel: (CanvasWheelInput) -> Bool = { _ in false }
    var radiusKey: (Int) -> Bool = { _ in false }
    var doubleClick: (() -> Void)? = nil
    var precisionKey: ((CanvasPrecisionKeyInput) -> Bool)? = nil
    var isRectangular = false
    var clickCancel: ((UUID) -> Void)?
    var admitsPrimaryPress: ((Int) -> Bool)?
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)?
    var retainVisibilityFocus: ((CanvasProfileFocusRequest) -> Void)?
    private var activation: (token: UUID, origin: NSPoint, isDragging: Bool, mode: GraphSelectionMode)?
    private weak var previousResponder: NSResponder?
    private weak var activationResponder: NSResponder?
    private var lostPrecisionFocus = false
    private(set) var pendingCancellation: Task<Void, Never>?

    func routeWheel(_ input: CanvasWheelInput) -> Bool { enabled && input.isSupported && wheel(input) }
    override func scrollWheel(with event: NSEvent) {
        if !routeWheel(CanvasWheelInput(event)) { super.scrollWheel(with: event) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard enabled, bounds.contains(local) else { return nil }
        if isRectangular { return self }
        let dx = local.x - bounds.midX
        let dy = local.y - bounds.midY
        return dx * dx + dy * dy <= 18 * 18 ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelActivation(deferred: true, restoringFocus: false)
        super.rightMouseDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        switch CanvasContextClick.decision(
            buttonNumber: event.buttonNumber, modifiers: event.modifierFlags, isAddingNodes: false)
        {
        case .showMenu:
            rightMouseDown(with: event)
            return
        case .cancelAdd: return
        case .unhandled:
            super.mouseDown(with: event)
            return
        case .primary: break
        }
        guard enabled else { return }
        if activation != nil { cancelActivation() }
        guard admitsPrimaryPress?(event.clickCount) != false else { return }
        var mode = GraphSelectionMode.pointerMode(modifiers: event.modifierFlags)
        // Non-graph handles keep their existing modifier behavior.
        if mode == .subtract && subtract == nil { mode = .toggle }
        if mode != .subtract, event.clickCount == 2, let doubleClick {
            window?.makeFirstResponder(self)
            doubleClick()
            return
        }
        let token = UUID()
        lostPrecisionFocus = false
        activationResponder = window?.firstResponder
        activation = (token, event.locationInWindow, false, mode)
        if precisionKey != nil, let window, window.firstResponder !== self {
            previousResponder = window.firstResponder
            guard window.makeFirstResponder(self) else {
                cancelActivation()
                return
            }
        }
        if canDrag && mode != .subtract {
            if event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.command), let beginShiftDrag {
                beginShiftDrag(token)
            } else {
                begin(token)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = activation else { return }
        guard current.mode != .subtract else { return }
        guard enabled, canDrag, !lostPrecisionFocus else {
            cancelActivation()
            return
        }
        let translation = displacement(from: current.origin, to: event.locationInWindow)
        guard current.isDragging || hypot(translation.x, translation.y) >= 3 else { return }
        if !current.isDragging, let window, window.firstResponder !== self {
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
        let mayFocus =
            !lostPrecisionFocus && (window?.firstResponder === self || window?.firstResponder === activationResponder)
        if precisionKey != nil, enabled, mayFocus {
            previousResponder = nil
            if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
        } else {
            restoreResponder()
        }
        defer {
            activationResponder = nil
            lostPrecisionFocus = false
        }
        guard enabled, !lostPrecisionFocus else {
            cancel(current.token)
            return
        }
        if current.isDragging && canDrag {
            finish(current.token, displacement(from: current.origin, to: event.locationInWindow))
        } else {
            if let clickCancel { clickCancel(current.token) } else { cancel(current.token) }
            switch current.mode {
            case .replace: select()
            case .add: add()
            case .toggle: toggle()
            case .subtract: subtract?()
            }
            window?.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, precisionKey != nil, let current = activation {
            lostPrecisionFocus = true
            // Responder changes can occur during SwiftUI updates. Invalidate admission now;
            // deliver the matching token cancellation after that update has completed.
            pendingCancellation = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.activation?.token == current.token, self.lostPrecisionFocus else { return }
                self.cancelActivation()
            }
        }
        return accepted
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        }
        if newWindow !== window || newWindow == nil {
            cancelActivation(deferred: true, restoringFocus: false)
        }
        super.viewWillMove(toWindow: newWindow)
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification, object: newWindow)
        }
    }

    func routeRadiusKey(_ event: NSEvent) -> Bool {
        guard enabled, activation == nil, window?.firstResponder === self,
            let direction = CanvasRadiusKey.direction(for: event)
        else { return false }
        return radiusKey(direction)
    }

    override func keyDown(with event: NSEvent) {
        // The captured precision handler admits keyboard edits independently of pointer picking.
        if activation == nil, superview != nil, let window, window.firstResponder === self {
            let input = CanvasPrecisionKeyInput(event)
            let ownsPartStateInput =
                window.isKeyWindow && window.attachedSheet == nil && window.sheetParent == nil
                && NSApp.modalWindow == nil
            if CanvasProfileSwitchKey.route(event, in: window, switchProfile: switchProfile) { return }
            if !input.isPartStateShortcut || ownsPartStateInput, precisionKey?(input) == true {
                if input.visibilityShortcut != nil, !input.isRepeat {
                    retainVisibilityFocus?(CanvasProfileFocusRequest(window: window))
                }
                return
            }
        }
        if routeRadiusKey(event) { return }
        guard event.keyCode == 53, activation != nil else {
            super.keyDown(with: event)
            return
        }
        cancelActivation()
    }

    @objc private func windowResigned() { cancelActivation() }

    func cancelActivation(deferred: Bool = false, restoringFocus: Bool = true) {
        guard let current = activation else { return }
        activation = nil
        if restoringFocus { restoreResponder() } else { previousResponder = nil }
        activationResponder = nil
        lostPrecisionFocus = false
        let callback = cancel
        if deferred {
            // Deliver the cancelled owner's callback/token, never a newer owner's callback.
            pendingCancellation = Task { @MainActor in
                await Task.yield()
                callback(current.token)
            }
        } else {
            callback(current.token)
        }
    }

    private func restoreResponder() {
        defer { previousResponder = nil }
        guard !lostPrecisionFocus, let window, window.firstResponder === self else { return }
        if let previous = previousResponder as? NSView, previous.window !== window { return }
        window.makeFirstResponder(previousResponder)
    }

    private func displacement(from origin: NSPoint, to point: NSPoint) -> CanvasPoint {
        .init(x: point.x - origin.x, y: origin.y - point.y)
    }
}
