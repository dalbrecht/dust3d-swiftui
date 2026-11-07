import AppKit
import Dust3DEditorModel
import SwiftUI

/// One native wheel activation is one signed step; phase-only and momentum events pass through.
struct CanvasWheelInput {
    let verticalDelta: Double
    var modifiers: NSEvent.ModifierFlags = []
    var phase: NSEvent.Phase = []
    var momentumPhase: NSEvent.Phase = []

    init(
        verticalDelta: Double, modifiers: NSEvent.ModifierFlags = [], phase: NSEvent.Phase = [],
        momentumPhase: NSEvent.Phase = []
    ) {
        self.verticalDelta = verticalDelta
        self.modifiers = modifiers
        self.phase = phase
        self.momentumPhase = momentumPhase
    }
    init(_ event: NSEvent) {
        self.init(
            verticalDelta: event.scrollingDeltaY, modifiers: event.modifierFlags, phase: event.phase,
            momentumPhase: event.momentumPhase)
    }
    var isSupported: Bool {
        verticalDelta.isFinite && verticalDelta != 0 && momentumPhase.isEmpty
            && (phase.isEmpty || phase == .began || phase == .changed)
    }
}

/// The local canvas responder owns background pointer input; node responders forward only their own wheel events.
struct CanvasPointerSurface: NSViewRepresentable {
    let enabled: Bool
    let select: (CanvasSelectionRectangle, GraphSelectionMode) -> Void
    let tap: (CanvasPoint, GraphSelectionMode) -> Void
    let rectangle: (CanvasSelectionRectangle?) -> Void
    let hover: (CanvasPoint?) -> Void
    let wheel: (CanvasWheelInput) -> Bool
    var radiusKey: (Int) -> Bool = { _ in false }
    var doubleClick: ((CanvasPoint) -> Void)? = nil
    var lassoCanvas: ReferenceColorCanvasIdentity? = nil
    var lassoSelection: (() -> (@MainActor (CanvasLasso, GraphSelectionMode) -> Void)?)? = nil
    var lassoPreview: (CanvasLasso?) -> Void = { _ in }
    var precisionKey: ((CanvasPrecisionKeyInput) -> Bool)? = nil
    var isAddingNodes = false
    var addPress: (CanvasPoint) -> Void = { _ in }
    var cancelInput: () -> Void = {}
    var admitsPrimaryPress: ((Int) -> Bool)? = nil
    var profileFocusRequest: CanvasProfileFocusRequest? = nil
    var ownsProfile: () -> Bool = { true }
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)? = nil

    func makeNSView(context: Context) -> CanvasPointerView { CanvasPointerView() }
    static func dismantleNSView(_ view: CanvasPointerView, coordinator: ()) {
        view.cancelActivation()
        view.enabled = false
        view.precisionKey = nil
        view.profileFocusRequest = nil
        view.switchProfile = nil
    }
    func updateNSView(_ view: CanvasPointerView, context: Context) {
        if !enabled { view.cancelActivation() }
        view.enabled = enabled
        view.select = select
        view.tap = tap
        view.rectangle = rectangle
        view.hover = hover
        view.wheel = wheel
        view.radiusKey = radiusKey
        view.doubleClick = doubleClick
        if view.lassoCanvas != lassoCanvas { view.cancelActivation() }
        view.lassoCanvas = lassoCanvas
        view.lassoSelection = lassoSelection
        view.lassoPreview = lassoPreview
        view.precisionKey = precisionKey
        if view.isAddingNodes != isAddingNodes { view.cancelActivation() }
        view.isAddingNodes = isAddingNodes
        view.addPress = addPress
        view.cancelInput = cancelInput
        view.admitsPrimaryPress = admitsPrimaryPress
        view.profileFocusRequest = profileFocusRequest
        view.ownsProfile = ownsProfile
        view.switchProfile = switchProfile
        view.scheduleProfileFocus()
    }
}

final class CanvasPointerView: NSView {
    var enabled = false { didSet { if oldValue && !enabled { cancelActivation() } } }
    var select: (CanvasSelectionRectangle, GraphSelectionMode) -> Void = { _, _ in }
    var tap: (CanvasPoint, GraphSelectionMode) -> Void = { _, _ in }
    var rectangle: (CanvasSelectionRectangle?) -> Void = { _ in }
    var hover: (CanvasPoint?) -> Void = { _ in }
    var wheel: (CanvasWheelInput) -> Bool = { _ in false }
    var radiusKey: (Int) -> Bool = { _ in false }
    var doubleClick: ((CanvasPoint) -> Void)? = nil
    var lassoCanvas: ReferenceColorCanvasIdentity? = nil
    var lassoSelection: (() -> (@MainActor (CanvasLasso, GraphSelectionMode) -> Void)?)? = nil
    var lassoPreview: (CanvasLasso?) -> Void = { _ in }
    var precisionKey: ((CanvasPrecisionKeyInput) -> Bool)? = nil
    var isAddingNodes = false
    var addPress: (CanvasPoint) -> Void = { _ in }
    var cancelInput: () -> Void = {}
    var admitsPrimaryPress: ((Int) -> Bool)? = nil
    var profileFocusRequest: CanvasProfileFocusRequest? = nil
    var ownsProfile: () -> Bool = { true }
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)? = nil
    private var start: (point: CanvasPoint, mode: GraphSelectionMode)?
    private var lassoGeneration = UUID()
    private var lasso: (path: CanvasLasso, select: @MainActor (CanvasLasso, GraphSelectionMode) -> Void)?
    private var tracking: NSTrackingArea?
    private var activity = CanvasPointerActivity()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self
        )
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }
    private func point(_ event: NSEvent) -> CanvasPoint {
        let point = convert(event.locationInWindow, from: nil)
        return .init(x: point.x, y: point.y)
    }
    override func rightMouseDown(with event: NSEvent) {
        invalidate()
        if isAddingNodes {
            cancelInput()
            return
        }
        super.rightMouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        if isAddingNodes {
            invalidate()
            cancelInput()
            return nil
        }
        return super.menu(for: event)
    }
    override func mouseDown(with event: NSEvent) {
        switch CanvasContextClick.decision(
            buttonNumber: event.buttonNumber, modifiers: event.modifierFlags, isAddingNodes: isAddingNodes)
        {
        case .showMenu, .cancelAdd:
            rightMouseDown(with: event)
            return
        case .unhandled:
            super.mouseDown(with: event)
            return
        case .primary: break
        }
        guard enabled else {
            super.mouseDown(with: event)
            return
        }
        guard admitsPrimaryPress?(event.clickCount) != false else {
            cancelActivation()
            return
        }
        window?.makeFirstResponder(self)
        if isAddingNodes {
            addPress(point(event))
            return
        }
        let mode = GraphSelectionMode.pointerMode(modifiers: event.modifierFlags)
        if mode != .subtract, event.clickCount == 2, let doubleClick {
            invalidate()
            doubleClick(point(event))
            return
        }
        let origin = point(event)
        lasso = nil
        lassoGeneration = UUID()
        if lassoCanvas != nil {
            guard let selectLasso = lassoSelection?() else { return }
            var path = CanvasLasso()
            path.append(origin)
            lasso = (path, selectLasso)
        }
        start = (origin, mode)
    }
    override func mouseDragged(with event: NSEvent) {
        if enabled && isAddingNodes {
            activity.hasHover = true
            hover(point(event))
            return
        }
        guard enabled, let start else { return }
        let end = point(event)
        let beyondThreshold = hypot(end.x - start.point.x, end.y - start.point.y) >= 3
        if lasso != nil {
            lasso?.path.append(end)
            if activity.hasMarquee || beyondThreshold {
                activity.hasMarquee = true
                lassoPreview(lasso?.path)
            }
        } else if beyondThreshold {
            activity.hasMarquee = true
            rectangle(.init(from: start.point, to: end))
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        var lasso = self.lasso
        self.lasso = nil
        let release = activity.finishMarquee()
        release.notify(rectangle: rectangle, hover: hover)
        guard enabled else { return }
        let end = point(event)
        let beyondThreshold = hypot(end.x - start.point.x, end.y - start.point.y) >= 3
        if lasso != nil && (release.clearsMarquee || beyondThreshold) {
            lasso?.path.append(end)
            if let lasso { lasso.select(lasso.path, start.mode) }
        } else if beyondThreshold {
            select(.init(from: start.point, to: end), start.mode)
        } else {
            tap(end, start.mode)
        }
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, lasso != nil {
            start = nil
            lasso = nil
            let release = activity.finishMarquee()
            if release.clearsMarquee {
                let generation = lassoGeneration
                Task { @MainActor [weak self] in
                    guard let self, self.lassoGeneration == generation else { return }
                    self.lassoPreview(nil)
                }
            }
        }
        return accepted
    }

    override func mouseEntered(with event: NSEvent) {
        if enabled {
            activity.hasHover = true
            hover(point(event))
        }
    }
    override func mouseMoved(with event: NSEvent) {
        if enabled {
            activity.hasHover = true
            hover(point(event))
        }
    }
    override func mouseExited(with event: NSEvent) {
        if activity.hasHover {
            activity.hasHover = false
            hover(nil)
        }
    }
    /// Lifecycle updates cancel native input only; SwiftUI lifecycle hooks clear presentation and hover.
    func cancelActivation() {
        start = nil
        lasso = nil
        lassoGeneration = UUID()
        activity = CanvasPointerActivity()
    }
    func invalidate() {
        start = nil
        lasso = nil
        lassoGeneration = UUID()
        let cancellation = activity.clear()
        cancellation.notify(rectangle: rectangle, hover: hover)
    }
    @objc private func windowResigned() {
        invalidate()
        if isAddingNodes { cancelInput() }
    }
    func routeRadiusKey(_ event: NSEvent) -> Bool {
        guard enabled, start == nil, window?.firstResponder === self,
            let direction = CanvasRadiusKey.direction(for: event)
        else { return false }
        return radiusKey(direction)
    }
    override func keyDown(with event: NSEvent) {
        // The captured precision handler admits keyboard edits independently of pointer picking.
        if start == nil, !activity.hasMarquee, superview != nil, let window, window.firstResponder === self {
            if CanvasProfileSwitchKey.route(event, in: window, switchProfile: switchProfile)
                || precisionKey?(CanvasPrecisionKeyInput(event)) == true
            {
                return
            }
        }
        if routeRadiusKey(event) { return }
        if event.keyCode == 53, start != nil || isAddingNodes {
            invalidate()
            if isAddingNodes { cancelInput() }
        } else {
            super.keyDown(with: event)
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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleProfileFocus()
    }

    func scheduleProfileFocus() {
        guard window != nil, profileFocusRequest?.isPending == true else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.profileFocusRequest?.claim(for: self, ownsProfile: self.ownsProfile())
        }
    }

    func routeWheel(_ input: CanvasWheelInput) -> Bool { enabled && input.isSupported && wheel(input) }
    override func scrollWheel(with event: NSEvent) {
        if !routeWheel(CanvasWheelInput(event)) { super.scrollWheel(with: event) }
    }
}
