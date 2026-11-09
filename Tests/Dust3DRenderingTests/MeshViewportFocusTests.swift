import AppKit
import XCTest

@testable import Dust3DRendering

@MainActor
final class MeshViewportFocusTests: XCTestCase {
    private final class ResponderView: NSView {
        override var acceptsFirstResponder: Bool { true }
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

        focus.bind(replacement)
        focus.unbind(first)
        XCTAssertTrue(focus.moveFocus(in: window))
        XCTAssertTrue(window.firstResponder === replacement)
        focus.unbind(replacement)
        XCTAssertFalse(focus.moveFocus(in: window))
    }
}
