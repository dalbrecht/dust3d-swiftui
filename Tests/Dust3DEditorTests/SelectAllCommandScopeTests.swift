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

    func testSelectAllTransfersBetweenNodeAndEdgeFocusAndRejectsCompetingFocus() {
        for (nodes, edges, text, expected) in [
            (true, false, false, EditorCommandScope.SelectAllDestination.nodes),
            (false, true, false, .edges),
            (true, true, false, .unavailable),
            (true, true, true, .text),
            (false, false, false, .graph),
        ] {
            XCTAssertEqual(
                EditorCommandScope.selectAllDestination(
                    nativeTextFocus: text, componentSidebarFocus: false, animationFocus: false,
                    edgeSidebarFocus: edges, nodesSidebarFocus: nodes),
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
