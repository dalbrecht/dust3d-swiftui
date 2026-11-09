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

    @discardableResult
    package func moveFocus(in window: NSWindow?) -> Bool {
        guard let view, let window, view.window === window, !view.isHiddenOrHasHiddenAncestor else { return false }
        return window.makeFirstResponder(view)
    }
}
