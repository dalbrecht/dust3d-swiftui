import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class NodeTaperSessionTests: XCTestCase {
    func testTaperIsIndependentOfAxisAndRadiusLocksAndHasExactUndoRedo() async throws {
        let source = try fixture()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        _ = try await session.select("a")
        for lock in EditingConstraint.allCases {
            _ = try await session.setLock(lock, isLocked: true)
        }
        let before = try await session.select("a")
        let initial = try XCTUnwrap(before.selectedNode)
        XCTAssertEqual(initial.deformationScale(.width), 0.5)
        XCTAssertEqual(initial.deformationScale(.thickness), 0.75)

        let edited = try await session.setNodeDeformationScale(
            .width, value: 1.25, nodeID: "a", target: CanvasAdjustmentTarget(snapshot: before))
        let updated = try XCTUnwrap(edited.selectedNode)
        XCTAssertEqual(updated.deformationScale(.width), 1.25)
        XCTAssertEqual(updated.deformationScale(.thickness), 0.75)
        XCTAssertEqual(updated.value, initial.value)
        XCTAssertEqual(edited.selectedIDs, before.selectedIDs)
        XCTAssertEqual(edited.locks, before.locks)
        XCTAssertNotEqual(edited.previewIdentity, before.previewIdentity)
        XCTAssertTrue(edited.canUndo)

        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertEqual(undone.previewIdentity, before.previewIdentity)
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), edited.document.encoded())
        XCTAssertEqual(redone.previewIdentity, edited.previewIdentity)
    }

    func testTaperRequiresTheSoleSelectedEditableModelNode() async throws {
        let source = try fixture()
        let session = EditorSession()
        let unselected = try await session.open(data: source.encoded())
        try await reject(session, nodeID: "a", snapshot: unselected)
        let multiple = try await session.select(["a", "b"])
        try await reject(session, nodeID: "a", snapshot: multiple)
        let selected = try await session.select("a")
        try await reject(session, nodeID: "b", snapshot: selected)
        let locked = try await session.select("locked")
        try await reject(session, nodeID: "locked", snapshot: locked)
        let profile = try await session.select("profile")
        try await reject(session, nodeID: "profile", snapshot: profile)
        let unchanged = try await session.select("a")
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertEqual(unchanged.previewIdentity, unselected.previewIdentity)
        XCTAssertFalse(unchanged.canUndo)
    }

    func testTaperRejectsAnOldTargetAfterSelectionReturns() async throws {
        let source = try fixture()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.select("a")
        _ = try await session.select("b")
        let returned = try await session.select("a")
        XCTAssertNotEqual(returned.selectionRevision, before.selectionRevision)
        try await reject(session, nodeID: "a", snapshot: before)
        let unchanged = try await session.select("a")
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertEqual(unchanged.documentRevision, before.documentRevision)
        XCTAssertFalse(unchanged.canUndo)
    }

    private func reject(_ session: EditorSession, nodeID: String, snapshot: EditorSnapshot) async throws {
        do {
            _ = try await session.setNodeDeformationScale(
                .width, value: 1.25, nodeID: nodeID, target: CanvasAdjustmentTarget(snapshot: snapshot))
            XCTFail("Taper edit unexpectedly accepted for \(nodeID)")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    private func fixture() throws -> Dust3DDocument {
        let xml = """
            <canvas><nodes>
            <node id='a' partId='p' x='0.1' y='0.2' z='0.3' radius='0.1' deformWidth='0.5' deformThickness='0.75'/>
            <node id='b' partId='p' x='0.4' y='0.5' z='0.6' radius='0.1'/>
            <node id='locked' partId='locked-part' x='0' y='0' z='0' radius='0.1'/>
            <node id='profile' partId='profile-part' x='0' y='0' z='0' radius='0.1'/>
            </nodes><parts><part id='p'/><part id='locked-part' locked='true'/>
            <part id='profile-part' target='CutFace'/></parts></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }
}
