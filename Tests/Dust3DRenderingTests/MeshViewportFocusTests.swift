import AppKit
import XCTest

@testable import Dust3DRendering

@MainActor
final class MeshViewportFocusTests: XCTestCase {
    private final class ResponderView: NSView {
        var canFocus = true
        override var acceptsFirstResponder: Bool { canFocus }
    }

    func testHostFocusFollowsOnlyTheCurrentVisibleViewport() {
        let focus = MeshViewportFocus()
        let window = NSWindow()
        let otherWindow = NSWindow()
        let viewport = ResponderView()
        let otherViewport = ResponderView()
        window.contentView?.addSubview(viewport)
        otherWindow.contentView?.addSubview(otherViewport)
        XCTAssertTrue(otherWindow.makeFirstResponder(otherViewport))

        XCTAssertFalse(focus.moveFocusInHostWindow())
        focus.bind(viewport)
        XCTAssertTrue(focus.moveFocusInHostWindow())
        XCTAssertTrue(window.firstResponder === viewport)
        XCTAssertTrue(otherWindow.firstResponder === otherViewport)

        viewport.isHidden = true
        XCTAssertFalse(focus.moveFocusInHostWindow())
        focus.unbind(viewport)
        XCTAssertFalse(focus.moveFocusInHostWindow())
    }

    func testFocusIsScopedToTheAttachedWindowAndRetiresOnlyTheMatchingView() {
        let focus = MeshViewportFocus()
        let window = NSWindow()
        let otherWindow = NSWindow()
        let first = ResponderView()
        let replacement = ResponderView()
        window.contentView?.addSubview(first)
        window.contentView?.addSubview(replacement)

        focus.bind(first)
        XCTAssertFalse(focus.moveFocus(in: nil))
        XCTAssertFalse(focus.moveFocus(in: otherWindow))
        XCTAssertTrue(focus.moveFocus(in: window))
        XCTAssertTrue(window.firstResponder === first)
        replacement.isHidden = true
        focus.bind(replacement)
        XCTAssertFalse(focus.moveFocus(in: window), "A hidden preview cannot receive focus")
        XCTAssertTrue(window.firstResponder === first)
        replacement.isHidden = false

        replacement.canFocus = false
        XCTAssertFalse(focus.moveFocus(in: window), "An unavailable preview cannot receive focus")
        XCTAssertTrue(window.firstResponder === first)
        replacement.canFocus = true

        focus.bind(replacement)
        focus.unbind(first)
        XCTAssertTrue(focus.moveFocus(in: window))
        XCTAssertTrue(window.firstResponder === replacement)
        focus.unbind(replacement)
        XCTAssertFalse(focus.moveFocus(in: window))
    }
}
