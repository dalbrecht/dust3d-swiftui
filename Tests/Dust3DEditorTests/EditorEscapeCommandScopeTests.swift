import XCTest

@testable import Dust3DEditor

final class EditorEscapeCommandScopeTests: XCTestCase {
    func testTextSheetAndAnimationKeepEscapeEvenWhenBothWindowActionsAreAvailable() {
        for (sheet, text, animation) in [(true, false, false), (false, true, false), (false, false, true)] {
            XCTAssertEqual(
                EditorCommandScope.escapeDestination(
                    hasKeyWindow: true, hasSheet: sheet, nativeTextFocus: text, animationFocus: animation,
                    hasCanvasInput: true, canCancelExport: true),
                .system)
        }
    }

    func testOnlyOneWindowActionOwnsBareEscapeAndNoWindowRegistersNeither() {
        XCTAssertEqual(
            EditorCommandScope.escapeDestination(
                hasKeyWindow: false, hasSheet: false, nativeTextFocus: false, animationFocus: false,
                hasCanvasInput: true, canCancelExport: true),
            .unavailable)
        XCTAssertEqual(
            EditorCommandScope.escapeDestination(
                hasKeyWindow: true, hasSheet: false, nativeTextFocus: false, animationFocus: false,
                hasCanvasInput: true, canCancelExport: true),
            .canvas)
        XCTAssertEqual(
            EditorCommandScope.escapeDestination(
                hasKeyWindow: true, hasSheet: false, nativeTextFocus: false, animationFocus: false,
                hasCanvasInput: false, canCancelExport: true),
            .export)
        XCTAssertEqual(
            EditorCommandScope.escapeDestination(
                hasKeyWindow: true, hasSheet: false, nativeTextFocus: false, animationFocus: false,
                hasCanvasInput: false, canCancelExport: false),
            .unavailable)
    }
}
