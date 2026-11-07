import AppKit
import XCTest

@testable import Dust3DEditor

final class CanvasAddModeKeyTests: XCTestCase {
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
