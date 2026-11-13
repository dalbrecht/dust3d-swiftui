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
    var wheelWhileDisabled: () -> Bool = { false }
    var unhandledWheel: ((CanvasWheelInput) -> Bool)? = nil
    var radiusKey: (Int) -> Bool = { _ in false }
    var doubleClick: ((CanvasPoint, GraphSelectionMode) -> Void)? = nil
    var lassoCanvas: ReferenceColorCanvasIdentity? = nil
    var lassoSelection: ((GraphSelectionMode) -> CanvasLassoInteraction?)? = nil
    var lassoPreview: (CanvasLassoSample?) -> Void = { _ in }
    var lassoFinish: (CanvasLassoSample) -> Void = { _ in }
    var precisionKey: ((CanvasPrecisionKeyInput) -> Bool)? = nil
    var tracksHoverWhileDisabled = false
    var isAddingNodes = false
    var addPress: (CanvasPoint) -> Void = { _ in }
    var cancelInput: () -> Void = {}
    var admitsPrimaryPress: ((Int) -> Bool)? = nil
    var profileFocusRequest: CanvasProfileFocusRequest? = nil
    var ownsProfile: () -> Bool = { true }
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)? = nil
    var focusControl: CanvasProfileFocusControl? = nil
    var focusTarget: CanvasProfileFocusTarget? = nil
    var addModeKey: CanvasAddModeKey.Handler? = nil

    func makeNSView(context: Context) -> CanvasPointerView { CanvasPointerView() }
    static func dismantleNSView(_ view: CanvasPointerView, coordinator: ()) {
        view.cancelActivation()
        view.enabled = false
        view.wheelWhileDisabled = { false }
        view.precisionKey = nil
        view.profileFocusRequest = nil
        view.switchProfile = nil
        view.focusControl?.detach(view)
        view.focusControl = nil
        view.addModeKey = nil
    }
    func updateNSView(_ view: CanvasPointerView, context: Context) {
        view.tracksHoverWhileDisabled = tracksHoverWhileDisabled
        if !enabled { view.cancelActivation(preservingHover: tracksHoverWhileDisabled) }
        view.enabled = enabled
        view.select = select
        view.tap = tap
        view.rectangle = rectangle
        view.hover = hover
        view.wheel = wheel
        view.wheelWhileDisabled = wheelWhileDisabled
        view.unhandledWheel = unhandledWheel
        view.radiusKey = radiusKey
        view.doubleClick = doubleClick
        if view.lassoCanvas != lassoCanvas { view.cancelActivation() }
        view.lassoCanvas = lassoCanvas
        view.lassoSelection = lassoSelection
        view.lassoPreview = lassoPreview
        view.lassoFinish = lassoFinish
        view.precisionKey = precisionKey
        if view.isAddingNodes != isAddingNodes { view.cancelActivation() }
        view.isAddingNodes = isAddingNodes
        view.addPress = addPress
        view.cancelInput = cancelInput
        view.admitsPrimaryPress = admitsPrimaryPress
        view.profileFocusRequest = profileFocusRequest
        view.ownsProfile = ownsProfile
        view.switchProfile = switchProfile
        view.focusControl = focusControl
        if let focusTarget, ownsProfile() { focusControl?.attach(view, target: focusTarget) }
        view.addModeKey = addModeKey
        view.scheduleProfileFocus()
    }
}

final class CanvasPointerView: NSView {
    var tracksHoverWhileDisabled = false
    var enabled = false {
        didSet { if oldValue && !enabled { cancelActivation(preservingHover: tracksHoverWhileDisabled) } }
    }
    var select: (CanvasSelectionRectangle, GraphSelectionMode) -> Void = { _, _ in }
    var tap: (CanvasPoint, GraphSelectionMode) -> Void = { _, _ in }
    var rectangle: (CanvasSelectionRectangle?) -> Void = { _ in }
    var hover: (CanvasPoint?) -> Void = { _ in }
    var wheel: (CanvasWheelInput) -> Bool = { _ in false }
    var wheelWhileDisabled: () -> Bool = { false }
    var unhandledWheel: ((CanvasWheelInput) -> Bool)?
    var radiusKey: (Int) -> Bool = { _ in false }
    var doubleClick: ((CanvasPoint, GraphSelectionMode) -> Void)? = nil
    var lassoCanvas: ReferenceColorCanvasIdentity? = nil
    var lassoSelection: ((GraphSelectionMode) -> CanvasLassoInteraction?)? = nil
    var lassoPreview: (CanvasLassoSample?) -> Void = { _ in }
    var lassoFinish: (CanvasLassoSample) -> Void = { _ in }
    var precisionKey: ((CanvasPrecisionKeyInput) -> Bool)? = nil
    var isAddingNodes = false
    var addPress: (CanvasPoint) -> Void = { _ in }
    var cancelInput: () -> Void = {}
    var admitsPrimaryPress: ((Int) -> Bool)? = nil
    var profileFocusRequest: CanvasProfileFocusRequest? = nil
    var ownsProfile: () -> Bool = { true }
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)? = nil
    weak var focusControl: CanvasProfileFocusControl?
    var addModeKey: CanvasAddModeKey.Handler? = nil
    private var start: (point: CanvasPoint, mode: GraphSelectionMode)?
    private var lassoPreviewGeneration = UUID()
    private var lasso: (path: CanvasLasso, interaction: CanvasLassoInteraction)?
    private var tracking: NSTrackingArea?
    private var activity = CanvasPointerActivity()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override class var defaultFocusRingType: NSFocusRingType { .exterior }

    override var focusRingMaskBounds: NSRect {
        // Leave room for the native ring inside the drawing pane.
        guard bounds.width > 8, bounds.height > 8 else { return .zero }
        return bounds.insetBy(dx: 4, dy: 4)
    }

    override func drawFocusRingMask() {
        NSBezierPath(rect: focusRingMaskBounds).fill()
    }

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
        if enabled {
            activity.hasHover = true
            hover(point(event))
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
            doubleClick(point(event), mode)
            return
        }
        let origin = point(event)
        lasso = nil
        if lassoCanvas != nil {
            guard let interaction = lassoSelection?(mode) else { return }
            var path = CanvasLasso()
            path.append(origin)
            lasso = (path, interaction)
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
                if !activity.hasMarquee { lassoPreviewGeneration = UUID() }
                activity.hasMarquee = true
                guard let lasso, lasso.interaction.isCurrent() else {
                    invalidate()
                    return
                }
                lassoPreview(.init(path: lasso.path, interaction: lasso.interaction))
            }
        } else if beyondThreshold {
            activity.hasMarquee = true
            rectangle(.init(from: start.point, to: end))
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        let lasso = self.lasso
        self.lasso = nil
        let release = activity.finishMarquee()
        guard enabled else {
            release.notify(rectangle: rectangle, hover: hover)
            return
        }
        let end = point(event)
        let beyondThreshold = hypot(end.x - start.point.x, end.y - start.point.y) >= 3
        if var active = lasso, release.clearsMarquee || beyondThreshold {
            active.path.append(end)
            lassoFinish(.init(path: active.path, interaction: active.interaction))
            return
        }
        release.notify(rectangle: rectangle, hover: hover)
        if beyondThreshold {
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
                let generation = lassoPreviewGeneration
                Task { @MainActor [weak self] in
                    guard let self, self.lassoPreviewGeneration == generation else { return }
                    self.lassoPreview(nil)
                }
            }
        }
        return accepted
    }

    override func mouseEntered(with event: NSEvent) {
        if enabled || tracksHoverWhileDisabled {
            activity.hasHover = true
            hover(point(event))
        }
    }
    override func mouseMoved(with event: NSEvent) {
        if enabled || tracksHoverWhileDisabled {
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
    func cancelActivation(preservingHover: Bool = false) {
        start = nil
        let hadHover = activity.hasHover
        lasso = nil
        activity = CanvasPointerActivity()
        activity.hasHover = preservingHover && hadHover
    }
    func invalidate() {
        start = nil
        lasso = nil
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
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if start == nil, !activity.hasMarquee, let window, window.firstResponder === self,
            let input = CanvasPrecisionKeyInput.alternateRedo(event), input.permitsDispatch(in: window),
            precisionKey?(input) == true
        {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // The captured precision handler admits keyboard edits independently of pointer picking.
        if start == nil, !activity.hasMarquee, superview != nil, let window, window.firstResponder === self {
            let input = CanvasPrecisionKeyInput(event)
            if CanvasProfileSwitchKey.route(event, in: window, switchProfile: switchProfile)
                || CanvasAddModeKey.route(event, in: window, handle: addModeKey)
                || (input.permitsDispatch(in: window) && precisionKey?(input) == true)
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

    func routeWheel(_ input: CanvasWheelInput, at point: CanvasPoint? = nil) -> Bool {
        guard input.isSupported, enabled || wheelWhileDisabled() else { return false }
        if enabled || tracksHoverWhileDisabled, !isAddingNodes, start == nil, let point {
            hover(point)
        }
        if wheel(input) { return true }
        return enabled && start == nil && unhandledWheel?(input) == true
    }

    override func scrollWheel(with event: NSEvent) {
        if !routeWheel(CanvasWheelInput(event), at: point(event)) {
            super.scrollWheel(with: event)
        }
    }
}
