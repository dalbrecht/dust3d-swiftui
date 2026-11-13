import AppKit
import XCTest

@testable import Dust3DEditor

final class CanvasAddModeKeyTests: XCTestCase {
    private final class SheetWindow: NSWindow {
        var presentedBy: NSWindow?
        override var sheetParent: NSWindow? { presentedBy }
        override var isKeyWindow: Bool { true }
    }

    @MainActor
    func testToolKeysLeaveSheetOwnedFocusAlone() async throws {
        let window = SheetWindow()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "a",
                charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        var received: [CanvasAddModeKey] = []
        let handle: CanvasAddModeKey.Handler = { key, _ in
            received.append(key)
            return true
        }

        window.presentedBy = NSWindow()
        XCTAssertFalse(CanvasAddModeKey.route(event, in: window, handle: handle))
        XCTAssertTrue(received.isEmpty)

        window.presentedBy = nil
        XCTAssertTrue(CanvasAddModeKey.route(event, in: window, handle: handle))
        XCTAssertEqual(received, [.toggleAdd])
    }

    func testBareAddAndSelectAcceptCapsLockAndConsumeRepeats() {
        for (key, expected): (String, CanvasAddModeKey) in [("a", .toggleAdd), ("s", .select)] {
            XCTAssertEqual(CanvasAddModeKey.disposition(characters: key, modifiers: [], isRepeat: false), expected)
            XCTAssertEqual(
                CanvasAddModeKey.disposition(characters: key.uppercased(), modifiers: .capsLock, isRepeat: false),
                expected)
            XCTAssertEqual(
                CanvasAddModeKey.disposition(characters: key, modifiers: [], isRepeat: true), .consumeRepeat)
        }
    }

    func testModifiedKeysAndUnrelatedTextFallThrough() {
        for modifier: NSEvent.ModifierFlags in [.command, .option, .shift, .control, .function] {
            for key in ["a", "s"] {
                XCTAssertEqual(
                    CanvasAddModeKey.disposition(characters: key, modifiers: modifier, isRepeat: false), .ignored)
            }
        }
        for key in ["", "as", "e", "å"] {
            XCTAssertEqual(CanvasAddModeKey.disposition(characters: key, modifiers: [], isRepeat: true), .ignored)
        }
    }
}
