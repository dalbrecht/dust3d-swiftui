import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class TransformAvailabilityTests: XCTestCase {
    private func makeState(withOrigin: Bool = false) throws -> EditorState {
        let origin = withOrigin ? "originX='0' originY='0' originZ='0'" : ""
        let xml = """
            <canvas \(origin)>
            <nodes>
            <node id='a' partId='p' x='0' y='0' z='0' radius='0.1'/>
            <node id='b' partId='p' x='1' y='2' z='3' radius='0.1'/>
            </nodes><edges><edge id='ab' from='a' to='b' partId='p'/></edges>
            <parts><part id='p'/></parts></canvas>
            """
        return try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
    }

    func testRotationRequiresOriginForSinglePivotButNotForCentroid() throws {
        var state = try makeState()
        try state.select("a")
        XCTAssertFalse(state.snapshot.canRotateSelection(in: .front))
        XCTAssertFalse(state.snapshot.canRotateSelection(in: .side))

        try state.selectGraph(nodes: [], edges: ["ab"])
        XCTAssertTrue(state.snapshot.canRotateSelection(in: .front))
        XCTAssertTrue(state.snapshot.canRotateSelection(in: .side))

        var withOrigin = try makeState(withOrigin: true)
        try withOrigin.select("a")
        XCTAssertTrue(withOrigin.snapshot.canRotateSelection(in: .front))
    }

    func testRotationUsesTheLocksOfItsOwnPlane() throws {
        var state = try makeState()
        try state.select(["a", "b"])
        state.setLock(.x, isLocked: true)
        state.setLock(.y, isLocked: true)
        XCTAssertFalse(state.snapshot.canRotateSelection(in: .front))
        XCTAssertTrue(state.snapshot.canRotateSelection(in: .side))

        state.setLock(.x, isLocked: false)
        state.setLock(.z, isLocked: true)
        XCTAssertTrue(state.snapshot.canRotateSelection(in: .front))
        XCTAssertFalse(state.snapshot.canRotateSelection(in: .side))
    }

    func testFlipAndAlignmentRequireAnAffectedAxisToBeUnlocked() throws {
        var state = try makeState()
        try state.select(["a", "b"])
        state.setLock(.x, isLocked: true)
        XCTAssertFalse(SelectionTransform.flipX.canApply(in: state.snapshot))
        XCTAssertTrue(SelectionTransform.flipZ.canApply(in: state.snapshot))
        XCTAssertFalse(SelectionTransform.frontAlignX.canApply(in: state.snapshot))
        XCTAssertTrue(SelectionTransform.frontAlignCenter.canApply(in: state.snapshot))

        state.setLock(.y, isLocked: true)
        XCTAssertFalse(SelectionTransform.frontAlignCenter.canApply(in: state.snapshot))
        XCTAssertTrue(SelectionTransform.sideAlignCenter.canApply(in: state.snapshot))
    }

    func testLocalAlignmentRequiresTwoEditableNodesButOriginAlignmentDoesNot() throws {
        var state = try makeState(withOrigin: true)
        try state.select("a")
        let local: [SelectionTransform] = [
            .frontAlignX, .frontAlignY, .frontAlignCenter, .sideAlignZ, .sideAlignY, .sideAlignCenter,
        ]
        for action in local { XCTAssertFalse(action.canApply(in: state.snapshot), action.rawValue) }
        XCTAssertTrue(SelectionTransform.originFrontX.canApply(in: state.snapshot))

        try state.selectGraph(nodes: [], edges: ["ab"])
        for action in local { XCTAssertTrue(action.canApply(in: state.snapshot), action.rawValue) }
    }

    func testOriginAlignmentRequiresAStoredOriginAndAnUnlockedAxis() throws {
        var withoutOrigin = try makeState()
        try withoutOrigin.select(["a", "b"])
        XCTAssertFalse(SelectionTransform.originFrontX.canApply(in: withoutOrigin.snapshot))
        XCTAssertTrue(SelectionTransform.frontAlignX.canApply(in: withoutOrigin.snapshot))

        var withOrigin = try makeState(withOrigin: true)
        try withOrigin.select(["a", "b"])
        XCTAssertTrue(SelectionTransform.originFrontX.canApply(in: withOrigin.snapshot))
        withOrigin.setLock(.x, isLocked: true)
        XCTAssertFalse(SelectionTransform.originFrontX.canApply(in: withOrigin.snapshot))
        XCTAssertTrue(SelectionTransform.originFrontCenter.canApply(in: withOrigin.snapshot))
    }

    func testExchangeUsesExplicitNodesAndBypassesAxisLocks() throws {
        var state = try makeState()
        try state.selectGraph(nodes: [], edges: ["ab"])
        XCTAssertFalse(SelectionTransform.exchangeXZ.canApply(in: state.snapshot))
        XCTAssertTrue(SelectionTransform.flipX.canApply(in: state.snapshot))

        try state.selectGraph(nodes: ["b"], edges: ["ab"])
        for lock in EditingConstraint.allCases {
            state.setLock(lock, isLocked: true)
        }
        XCTAssertTrue(SelectionTransform.exchangeXZ.canApply(in: state.snapshot))
        XCTAssertFalse(SelectionTransform.frontClockwise.canApply(in: state.snapshot))
    }
}
