import AppKit
import XCTest

@testable import Dust3DEditor

final class CanvasContextClickTests: XCTestCase {
    func testSecondaryClickCancelsAddAndOtherwiseRequestsContextMenu() {
        for modifiers: NSEvent.ModifierFlags in [[], .shift, [.command, .option, .control]] {
            XCTAssertEqual(
                CanvasContextClick.decision(buttonNumber: 1, modifiers: modifiers, isAddingNodes: true), .cancelAdd)
            XCTAssertEqual(
                CanvasContextClick.decision(buttonNumber: 1, modifiers: modifiers, isAddingNodes: false), .showMenu)
        }
    }
    func testControlClickHasTheSameSecondaryMeaningWithoutPrimaryPlacement() {
        for modifiers: NSEvent.ModifierFlags in [.control, [.control, .shift], [.control, .command]] {
            XCTAssertEqual(
                CanvasContextClick.decision(buttonNumber: 0, modifiers: modifiers, isAddingNodes: true), .cancelAdd)
            XCTAssertEqual(
                CanvasContextClick.decision(buttonNumber: 0, modifiers: modifiers, isAddingNodes: false), .showMenu)
        }
    }
    func testPrimarySelectionAndPlacementModifiersRemainPrimary() {
        for modifiers: NSEvent.ModifierFlags in [[], .shift, .command, .option, [.command, .shift], .capsLock] {
            for adding in [true, false] {
                XCTAssertEqual(
                    CanvasContextClick.decision(buttonNumber: 0, modifiers: modifiers, isAddingNodes: adding), .primary)
            }
        }
    }
    func testOtherButtonsNeverAcquirePrimaryOrContextIntent() {
        for button in [-1, 2, 3, Int.max] {
            XCTAssertEqual(
                CanvasContextClick.decision(buttonNumber: button, modifiers: .control, isAddingNodes: true), .unhandled)
        }
    }
}
