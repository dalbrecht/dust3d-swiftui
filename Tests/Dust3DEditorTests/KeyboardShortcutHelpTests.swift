import XCTest

@testable import Dust3DEditor

final class KeyboardShortcutHelpTests: XCTestCase {
    func testGroupNavigationShortcutsDescribeSidebarFocus() throws {
        let browse = try XCTUnwrap(KeyboardShortcutHelp.matching("⌘↓").first)
        XCTAssertEqual(browse.action, "Browse Selected Component Group")
        XCTAssertEqual(browse.scope, "Focused component sidebar with one visible group selected")
        let parent = try XCTUnwrap(KeyboardShortcutHelp.matching("⌘↑").first)
        XCTAssertEqual(parent.action, "Go to Enclosing Component Group")
        XCTAssertEqual(parent.scope, "Focused component sidebar while browsing a group")
    }

    func testSymbolicShortcutKeysHaveSpokenNamesAndCanBeSearchedByName() {
        let zoom = KeyboardShortcutHelp.Entry(action: "Zoom", keys: "⌥- / ⌥=", scope: "Focused editor window")
        let orbit = KeyboardShortcutHelp.Entry(action: "Orbit", keys: "← / → / ↑ / ↓", scope: "Focused preview")
        let gesture = KeyboardShortcutHelp.Entry(action: "Remove", keys: "⌥⌘ click / drag", scope: "Focused canvas")
        XCTAssertEqual(zoom.spokenKeys, "Option Minus or Option Equals")
        XCTAssertEqual(orbit.spokenKeys, "Left Arrow or Right Arrow or Up Arrow or Down Arrow")
        XCTAssertEqual(gesture.spokenKeys, "Option Command click or drag")
        XCTAssertEqual(KeyboardShortcutHelp.matching("Option Equals", in: [zoom, orbit, gesture]), [zoom])
        XCTAssertEqual(KeyboardShortcutHelp.matching("left arrow", in: [zoom, orbit, gesture]), [orbit])
    }

    func testExactKeySearchReturnsEveryBindingWithoutScopeSubstringMatches() {
        let entries = [
            KeyboardShortcutHelp.Entry(action: "Wireframe", keys: "W", scope: "Focused editor window"),
            KeyboardShortcutHelp.Entry(action: "Other W action", keys: "Q / W", scope: "Focused canvas"),
            KeyboardShortcutHelp.Entry(action: "Zoom Preview", keys: "⌥- / ⌥=", scope: "Focused editor window"),
        ]
        XCTAssertEqual(KeyboardShortcutHelp.matching(" w ", in: entries), Array(entries.prefix(2)))
        XCTAssertEqual(KeyboardShortcutHelp.matching("⌥=", in: entries), [entries[2]])
        XCTAssertEqual(KeyboardShortcutHelp.matching("window", in: entries), [entries[0], entries[2]])
    }

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
