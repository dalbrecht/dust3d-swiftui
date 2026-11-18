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

    func testExplicitExportCancellationDoesNotDependOnEscapeOwnership() {
        for (text, animation, canvas) in [(true, false, false), (false, true, false), (false, false, true)] {
            XCTAssertTrue(
                EditorCommandScope.canOfferExportCancellation(
                    hasKeyWindow: true, hasSheet: false, canCancelExport: true))
            XCTAssertEqual(
                EditorCommandScope.escapeDestination(
                    hasKeyWindow: true, hasSheet: false, nativeTextFocus: text, animationFocus: animation,
                    hasCanvasInput: canvas, canCancelExport: true),
                canvas ? .canvas : .system)
        }
        XCTAssertFalse(
            EditorCommandScope.canOfferExportCancellation(
                hasKeyWindow: false, hasSheet: false, canCancelExport: true))
        XCTAssertFalse(
            EditorCommandScope.canOfferExportCancellation(
                hasKeyWindow: true, hasSheet: true, canCancelExport: true))
        XCTAssertFalse(
            EditorCommandScope.canOfferExportCancellation(
                hasKeyWindow: true, hasSheet: false, canCancelExport: false))
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
