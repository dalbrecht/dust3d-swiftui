import XCTest

@testable import Dust3DEditor

@MainActor
private final class PreviewDisplayRecords {
    var current = true
    var wireframe = false
    var colors = true
    var writes: [String] = []
}

@MainActor
final class EditorPreviewDisplayActionsTests: XCTestCase {
    func testOrdinaryActionsReadAndWriteBothDisplayPreferences() {
        let records = PreviewDisplayRecords()
        let actions = EditorPreviewDisplayActions(
            wireframe: { records.wireframe },
            setWireframe: {
                records.wireframe = $0
                records.writes.append("wireframe")
            },
            modelColors: { records.colors },
            setModelColors: {
                records.colors = $0
                records.writes.append("colors")
            })
        XCTAssertTrue(actions.canChangeWireframe)
        XCTAssertTrue(actions.canChangeModelColors)
        XCTAssertFalse(actions.isWireframe)
        XCTAssertTrue(actions.showsModelColors)
        actions.setWireframe(true)
        actions.setModelColors(false)
        XCTAssertTrue(actions.isWireframe)
        XCTAssertFalse(actions.showsModelColors)
        XCTAssertEqual(records.writes, ["wireframe", "colors"])
    }

    func testRestActionsChangeOnlyVisibleRestWireframe() {
        let ordinary = PreviewDisplayRecords()
        let rest = PreviewDisplayRecords()
        let actions = EditorPreviewDisplayActions(
            wireframe: { rest.wireframe }, setWireframe: { rest.wireframe = $0 })
        XCTAssertTrue(actions.canChangeWireframe)
        XCTAssertFalse(actions.canChangeModelColors)
        XCTAssertFalse(actions.showsModelColors)
        actions.setWireframe(true)
        actions.setModelColors(false)
        XCTAssertTrue(rest.wireframe)
        XCTAssertFalse(ordinary.wireframe)
        XCTAssertTrue(ordinary.colors)
    }

    func testCapturedActionsRejectInvalidatedPresentationAtInvocation() {
        let records = PreviewDisplayRecords()
        let actions = EditorPreviewDisplayActions(
            isCurrent: { records.current }, wireframe: { records.wireframe },
            setWireframe: { _ in records.writes.append("wireframe") }, modelColors: { records.colors },
            setModelColors: { _ in records.writes.append("colors") })
        records.current = false
        XCTAssertFalse(actions.canChangeWireframe)
        XCTAssertFalse(actions.canChangeModelColors)
        XCTAssertFalse(actions.isWireframe)
        XCTAssertFalse(actions.showsModelColors)
        actions.setWireframe(true)
        actions.setModelColors(false)
        XCTAssertTrue(records.writes.isEmpty)
    }

    func testIncompleteOptionalColorAccessIsUnavailable() {
        let records = PreviewDisplayRecords()
        let getterOnly = EditorPreviewDisplayActions(
            wireframe: { false }, setWireframe: { _ in }, modelColors: { true })
        let setterOnly = EditorPreviewDisplayActions(
            wireframe: { false }, setWireframe: { _ in },
            setModelColors: { _ in records.writes.append("colors") })
        for actions in [getterOnly, setterOnly] {
            XCTAssertFalse(actions.canChangeModelColors)
            XCTAssertFalse(actions.showsModelColors)
            actions.setModelColors(false)
        }
        XCTAssertTrue(records.writes.isEmpty)
    }
}
