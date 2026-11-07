import XCTest

@testable import Dust3DEditor

final class GraphDeleteFocusTests: XCTestCase {
    func testEitherTextFocusSignalBlocksGraphDelete() {
        for (swiftUIFocus, hasNativeEditor, allowsDelete) in [
            (false, false, true), (true, false, false), (false, true, false), (true, true, false),
        ] {
            let textFocus = EditorCommandScope.hasTextEditingFocus(
                swiftUIFocus: swiftUIFocus, hasNativeEditor: hasNativeEditor)
            XCTAssertEqual(
                EditorCommandScope.allowsGraphDelete(
                    animationFocus: false, nativeTextFocus: textFocus, componentSidebarFocus: false),
                allowsDelete)
        }
    }

    func testGraphDeleteAdmissionTracksFocusChangingAfterMenuValidation() {
        func canDelete(hasNativeEditor: Bool) -> Bool {
            EditorCommandScope.allowsGraphDelete(
                animationFocus: false,
                nativeTextFocus: EditorCommandScope.hasTextEditingFocus(
                    swiftUIFocus: false, hasNativeEditor: hasNativeEditor),
                componentSidebarFocus: false)
        }
        XCTAssertTrue(canDelete(hasNativeEditor: false))
        XCTAssertFalse(canDelete(hasNativeEditor: true))
        XCTAssertTrue(canDelete(hasNativeEditor: false))
    }
}
