import Dust3DRendering
import XCTest

@testable import Dust3DEditor

@MainActor
private final class PreviewCameraActionRecords {
    var calls: [String] = []
    var ordinaryCalls = 0
    var current = true
}

@MainActor
final class EditorPreviewCameraActionsTests: XCTestCase {
    func testReadyActionsDispatchCameraAndFitInOrder() {
        let records = PreviewCameraActionRecords()
        let actions = EditorPreviewCameraActions(
            canMove: true, move: { records.calls.append(String(describing: $0)) }, fit: { records.calls.append("fit") })
        XCTAssertTrue(actions.canMove)
        XCTAssertTrue(actions.supportsAutomaticOrbit)
        XCTAssertTrue(actions.canAutomaticallyOrbit)
        actions.move(.orbitLeft)
        actions.move(.zoomOut)
        actions.fit()
        XCTAssertEqual(records.calls, ["orbitLeft", "zoomOut", "fit"])
    }

    func testRestActionsNeverDispatchToOrdinaryActions() {
        let records = PreviewCameraActionRecords()
        let ordinary = EditorPreviewCameraActions(
            canMove: true, move: { _ in records.ordinaryCalls += 1 }, fit: { records.ordinaryCalls += 1 })
        let rest = EditorPreviewCameraActions(
            canMove: true, supportsAutomaticOrbit: false,
            move: { records.calls.append(String(describing: $0)) }, fit: { records.calls.append("fit") })
        var selectedActions: EditorPreviewCameraActions?
        selectedActions = ordinary
        selectedActions = rest
        selectedActions?.move(.panRight)
        selectedActions?.fit()
        XCTAssertEqual(records.calls, ["panRight", "fit"])
        XCTAssertEqual(records.ordinaryCalls, 0)
        XCTAssertFalse(selectedActions?.canAutomaticallyOrbit ?? true)
    }

    func testUnavailableRestActionsDoNotFallBackToOrdinaryCamera() {
        let records = PreviewCameraActionRecords()
        let unavailable = EditorPreviewCameraActions(
            canMove: false, supportsAutomaticOrbit: false,
            move: { _ in records.calls.append("move") }, fit: { records.calls.append("fit") })
        XCTAssertFalse(unavailable.canMove)
        XCTAssertFalse(unavailable.canAutomaticallyOrbit)
        unavailable.move(.orbitRight)
        unavailable.fit()
        XCTAssertTrue(records.calls.isEmpty)
    }

    func testCapturedActionsRejectModeChangesAtInvocation() {
        let records = PreviewCameraActionRecords()
        let captured = EditorPreviewCameraActions(
            canMove: true, isCurrent: { records.current },
            move: { records.calls.append(String(describing: $0)) }, fit: { records.calls.append("fit") })
        captured.move(.panUp)
        XCTAssertTrue(captured.canAutomaticallyOrbit)
        records.current = false
        XCTAssertFalse(captured.canMove)
        XCTAssertFalse(captured.canAutomaticallyOrbit)
        captured.move(.panDown)
        captured.fit()
        XCTAssertEqual(records.calls, ["panUp"])
    }

    func testRetainedMenuCameraRequiresItsWindowAndPresentation() {
        let records = PreviewCameraActionRecords()
        let window = PreviewCameraActionRecords()
        let actions = EditorPreviewCameraActions(
            canMove: true, isCurrent: { records.current },
            move: { records.calls.append(String(describing: $0)) }, fit: { records.calls.append("fit") },
            wheelZoom: { records.calls.append("wheel \($0)") })
        let menu = actions.scoped(to: { window.current })
        window.current = false
        XCTAssertFalse(menu.canMove)
        XCTAssertFalse(menu.canAutomaticallyOrbit)
        XCTAssertFalse(menu.canZoomFromCanvas)
        menu.move(.zoomIn)
        menu.fit()
        XCTAssertFalse(menu.zoomFromCanvas(step: 1))
        XCTAssertTrue(records.calls.isEmpty)

        window.current = true
        XCTAssertTrue(menu.canAutomaticallyOrbit)
        menu.move(.zoomOut)
        menu.fit()
        XCTAssertTrue(menu.zoomFromCanvas(step: -1))
        records.current = false
        menu.fit()
        XCTAssertEqual(records.calls, ["zoomOut", "fit", "wheel -1"])
    }

    func testAutomaticOrbitRequiresSupportedReadyCurrentPresentation() {
        for (ready, supported, current, expected) in [
            (false, true, true, false), (true, false, true, false),
            (true, true, false, false), (true, true, true, true),
        ] {
            let actions = EditorPreviewCameraActions(
                canMove: ready, supportsAutomaticOrbit: supported, isCurrent: { current },
                move: { _ in }, fit: {})
            XCTAssertEqual(actions.canAutomaticallyOrbit, expected)
            XCTAssertEqual(actions.supportsAutomaticOrbit, supported)
        }
    }

    func testAbsentActionTargetHasNoCameraOrAutomaticOrbitAvailability() {
        let records = PreviewCameraActionRecords()
        var selectedActions: EditorPreviewCameraActions?
        XCTAssertNil(selectedActions)
        selectedActions = EditorPreviewCameraActions(
            canMove: true, move: { _ in records.calls.append("move") }, fit: { records.calls.append("fit") })
        XCTAssertTrue(selectedActions?.canMove == true)
        selectedActions = nil
        XCTAssertFalse(selectedActions?.canMove == true)
        XCTAssertFalse(selectedActions?.canAutomaticallyOrbit == true)
        selectedActions?.move(.zoomIn)
        selectedActions?.fit()
        XCTAssertTrue(records.calls.isEmpty)
    }
}
