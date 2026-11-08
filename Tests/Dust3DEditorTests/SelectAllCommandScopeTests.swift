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

    func testNodesSidebarFocusSelectsNodesAndDefersToTextAndAnimation() {
        for (text, animation, expected) in [
            (false, false, EditorCommandScope.SelectAllDestination.nodes),
            (true, false, .text),
            (false, true, .unavailable),
        ] {
            XCTAssertEqual(
                EditorCommandScope.selectAllDestination(
                    nativeTextFocus: text, componentSidebarFocus: false, animationFocus: animation,
                    nodesSidebarFocus: true),
                expected)
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
}
