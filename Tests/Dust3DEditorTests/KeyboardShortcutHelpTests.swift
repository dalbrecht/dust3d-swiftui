import XCTest

@testable import Dust3DEditor

final class KeyboardShortcutHelpTests: XCTestCase {
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
}
