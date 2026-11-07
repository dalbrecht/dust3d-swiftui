import AppKit
import XCTest

@testable import Dust3DEditor

final class CanvasProfileSwitchKeyTests: XCTestCase {
    func testBareEAndCapsLockedEActivateTheOtherProfile() {
        XCTAssertEqual(
            CanvasProfileSwitchKey.disposition(characters: "e", modifiers: [], isRepeat: false),
            .switchProfile)
        XCTAssertEqual(
            CanvasProfileSwitchKey.disposition(characters: "E", modifiers: .capsLock, isRepeat: false),
            .switchProfile)
    }

    func testModifiedAndUnrelatedInputFallsThrough() {
        for modifier: NSEvent.ModifierFlags in [.command, .shift, .option, .control, .function] {
            XCTAssertEqual(
                CanvasProfileSwitchKey.disposition(characters: "e", modifiers: modifier, isRepeat: false),
                .ignored)
        }
        XCTAssertEqual(
            CanvasProfileSwitchKey.disposition(characters: "E", modifiers: [.capsLock, .shift], isRepeat: true),
            .ignored)
        for characters in ["", "ee", "r", "é"] {
            XCTAssertEqual(
                CanvasProfileSwitchKey.disposition(characters: characters, modifiers: [], isRepeat: false),
                .ignored)
        }
    }

    func testBareKeyRepeatsAreConsumedWithoutSwitchingAgain() {
        XCTAssertEqual(
            CanvasProfileSwitchKey.disposition(characters: "e", modifiers: [], isRepeat: true),
            .consumeRepeat)
        XCTAssertEqual(
            CanvasProfileSwitchKey.disposition(characters: "E", modifiers: .capsLock, isRepeat: true),
            .consumeRepeat)
    }
}
