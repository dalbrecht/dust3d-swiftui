import Dust3DRendering
import SwiftUI

/// One scene's visible preview target. Captured actions recheck their source and
/// presentation before dispatch; unavailable rest previews never fall back to a
/// hidden ordinary-model camera.
@MainActor
struct EditorPreviewCameraActions {
    let supportsAutomaticOrbit: Bool
    private let available: Bool
    private let isCurrent: @MainActor () -> Bool
    private let moveAction: @MainActor (MeshCameraCommand.Action) -> Void
    private let fitAction: @MainActor () -> Void
    private let wheelZoomAction: (@MainActor (Int) -> Void)?
    private let beginDragAction: (@MainActor () -> MeshViewportFocus.CanvasDrag?)?

    init(
        canMove: Bool, supportsAutomaticOrbit: Bool = true,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        move: @escaping @MainActor (MeshCameraCommand.Action) -> Void,
        fit: @escaping @MainActor () -> Void, wheelZoom: (@MainActor (Int) -> Void)? = nil,
        beginDrag: (@MainActor () -> MeshViewportFocus.CanvasDrag?)? = nil
    ) {
        available = canMove
        self.supportsAutomaticOrbit = supportsAutomaticOrbit
        self.isCurrent = isCurrent
        moveAction = move
        fitAction = fit
        wheelZoomAction = wheelZoom
        beginDragAction = beginDrag
    }

    var canMove: Bool { available && isCurrent() }
    var canAutomaticallyOrbit: Bool { supportsAutomaticOrbit && canMove }

    var canZoomFromCanvas: Bool { canMove && wheelZoomAction != nil }

    func zoomFromCanvas(step: Int) -> Bool {
        guard canZoomFromCanvas, let wheelZoomAction else { return false }
        wheelZoomAction(step)
        return true
    }

    func beginCanvasDrag() -> MeshViewportFocus.CanvasDrag? {
        guard canMove else { return nil }
        return beginDragAction?()
    }

    func move(_ action: MeshCameraCommand.Action) {
        guard canMove else { return }
        moveAction(action)
    }

    func fit() {
        guard canMove else { return }
        fitAction()
    }
}

private struct EditorPreviewCameraActionsKey: FocusedValueKey { typealias Value = EditorPreviewCameraActions }

extension FocusedValues {
    var editorPreviewCameraActions: EditorPreviewCameraActions? {
        get { self[EditorPreviewCameraActionsKey.self] }
        set { self[EditorPreviewCameraActionsKey.self] = newValue }
    }
}
