import AppKit

/// The scene owns this target while the representable lends its current AppKit view.
@MainActor
package final class MeshViewportFocus {
    private weak var view: NSView?

    package init() {}

    func bind(_ view: NSView) { self.view = view }

    func unbind(_ view: NSView) {
        if self.view === view { self.view = nil }
    }

    package typealias CanvasDrag = (update: @MainActor (SIMD2<Float>, Bool) -> Bool, end: @MainActor () -> Void)

    package func beginCanvasDrag() -> CanvasDrag? {
        guard let viewport = view as? InteractiveMeshView, viewport.window?.isKeyWindow == true,
            !viewport.isHiddenOrHasHiddenAncestor, let token = viewport.beginCanvasDrag()
        else { return nil }
        return (
            update: { [weak self, weak viewport] delta, pans in
                guard let self, let viewport, self.view === viewport, viewport.window?.isKeyWindow == true,
                    !viewport.isHiddenOrHasHiddenAncestor
                else { return false }
                return viewport.updateCanvasDrag(token, by: delta, pans: pans)
            },
            end: { [weak viewport] in viewport?.endCanvasDrag(token) }
        )
    }

    @discardableResult
    package func moveFocus(in window: NSWindow?) -> Bool {
        guard let view, let window, view.window === window, !view.isHiddenOrHasHiddenAncestor else { return false }
        return window.makeFirstResponder(view)
    }
}
