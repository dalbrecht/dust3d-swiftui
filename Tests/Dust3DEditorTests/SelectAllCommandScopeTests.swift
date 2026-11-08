import XCTest

@testable import Dust3DEditor

final class SelectAllCommandScopeTests: XCTestCase {
    func testNativeTextTakesPrecedenceOverOtherFocus() {
        for sidebar in [false, true] {
            for animation in [false, true] {
                XCTAssertEqual(
                    EditorCommandScope.selectAllDestination(
                        nativeTextFocus: true, componentSidebarFocus: sidebar, animationFocus: animation),
                    .text)
            }
        }
    }

    func testAnimationFocusDisablesSelectAll() {
        XCTAssertEqual(
            EditorCommandScope.selectAllDestination(
                nativeTextFocus: false, componentSidebarFocus: false, animationFocus: true),
            .unavailable)
        XCTAssertEqual(
            EditorCommandScope.selectAllDestination(
                nativeTextFocus: false, componentSidebarFocus: true, animationFocus: true),
            .unavailable)
    }

    func testSidebarFocusSelectsComponentsAndDefaultFocusSelectsGraph() {
        XCTAssertEqual(
            EditorCommandScope.selectAllDestination(
                nativeTextFocus: false, componentSidebarFocus: true, animationFocus: false),
            .components)
        XCTAssertEqual(
            EditorCommandScope.selectAllDestination(
                nativeTextFocus: false, componentSidebarFocus: false, animationFocus: false),
            .graph)
    }

    func testEdgeSidebarFocusRoutesOnlyToEdgesWithTextAndAnimationPrecedence() {
        XCTAssertEqual(
            EditorCommandScope.selectAllDestination(
                nativeTextFocus: false, componentSidebarFocus: false, animationFocus: false, edgeSidebarFocus: true),
            .edges)
        XCTAssertEqual(
            EditorCommandScope.selectAllDestination(
                nativeTextFocus: true, componentSidebarFocus: false, animationFocus: false, edgeSidebarFocus: true),
            .text)
        XCTAssertEqual(
            EditorCommandScope.selectAllDestination(
                nativeTextFocus: false, componentSidebarFocus: false, animationFocus: true, edgeSidebarFocus: true),
            .unavailable)
    }
}
