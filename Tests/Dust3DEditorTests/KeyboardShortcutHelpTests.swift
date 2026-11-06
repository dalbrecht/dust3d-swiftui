import XCTest

@testable import Dust3DEditor

final class KeyboardShortcutHelpTests: XCTestCase {
    func testInspectorVisibilityShortcutMatchesNativeWindowCommand() throws {
        let entry = try XCTUnwrap(KeyboardShortcutHelp.entries.first { $0.action == "Show / Hide Inspector" })
        XCTAssertEqual(entry.keys, "⌃⌘I")
        XCTAssertEqual(entry.scope, "Focused editor window")
    }

    func testSearchFindsActionsKeysAndFocusScopeWithoutChangingOrder() {
        let entries = [
            KeyboardShortcutHelp.Entry(action: "Rotate Selection", keys: ", / .", scope: "Canvas selection"),
            KeyboardShortcutHelp.Entry(action: "Copy", keys: "⌘C", scope: "Focused text or nodes"),
        ]
        XCTAssertEqual(KeyboardShortcutHelp.matching("  cAnVaS  ", in: entries), [entries[0]])
        XCTAssertEqual(KeyboardShortcutHelp.matching("⌘C", in: entries), [entries[1]])
        XCTAssertEqual(KeyboardShortcutHelp.matching("copy", in: entries), [entries[1]])
        XCTAssertEqual(KeyboardShortcutHelp.matching(" \n ", in: entries), entries)
        XCTAssertTrue(KeyboardShortcutHelp.matching("unimplemented", in: entries).isEmpty)
    }
    func testActualCatalogMakesFocusedRadiusAndOriginNudgingDiscoverable() {
        let focused = KeyboardShortcutHelp.matching("Focused canvas")
        XCTAssertTrue(focused.contains { $0.action == "Decrease / Increase Radius" })
        XCTAssertTrue(KeyboardShortcutHelp.matching("-").contains { $0.action == "Decrease / Increase Radius" })
        let originNudges = KeyboardShortcutHelp.matching("origin").filter { $0.keys == "← / → / ↑ / ↓" }
        XCTAssertEqual(originNudges.count, 1)
    }

}
