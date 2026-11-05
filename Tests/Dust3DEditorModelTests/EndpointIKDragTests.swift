import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EndpointIKDragTests: XCTestCase {
    private func archive() throws -> Dust3DDocument {
        let xml = """
            <canvas><nodes>
            <node id='root' partId='p' x='0' y='0' z='0' radius='.2'/>
            <node id='joint' partId='p' x='1' y='0' z='.25' radius='.2'/>
            <node id='tip' partId='p' x='2' y='0' z='.5' radius='.1'/>
            <node id='other' partId='p' x='0' y='1' z='0' radius='.1'/>
            <node id='third' partId='p' x='0' y='-1' z='0' radius='.1'/>
            </nodes><edges>
            <edge id='a' partId='p' from='root' to='joint'/>
            <edge id='b' partId='p' from='joint' to='tip'/>
            <edge id='c' partId='p' from='root' to='other'/>
            <edge id='d' partId='p' from='root' to='third'/>
            </edges><parts><part id='p'/></parts></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }

    func testBranchRootAndLockedAxisStayFixedWithExactUndo() async throws {
        let original = try archive()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select("tip")
        let initial = try await session.setLock(.z, isLocked: true)
        let projection = CanvasProjection(bounds: .init(nodes: initial.nodes), plane: .front, width: 400, height: 400)
        XCTAssertNil(EndpointIKTarget(endpointID: "root", snapshot: initial))
        XCTAssertNil(EndpointIKTarget(endpointID: "joint", snapshot: initial))
        let drag = try CanvasShiftDrag(anchorID: "tip", snapshot: initial, projection: projection)
        let result = try await session.commitCanvasShiftDrag(drag, translation: .init(x: -30, y: -60))
        XCTAssertEqual(result.selectedID, "tip")
        let old = Dictionary(uniqueKeysWithValues: initial.nodes.map { ($0.id, $0.value) })
        let new = Dictionary(uniqueKeysWithValues: result.nodes.map { ($0.id, $0.value) })
        for id in ["root", "other", "third"] { XCTAssertEqual(new[id], old[id]) }
        for id in ["joint", "tip"] {
            XCTAssertNotEqual(new[id]?.position, old[id]?.position)
            XCTAssertEqual(new[id]?.position.z, old[id]?.position.z)
            XCTAssertEqual(new[id]?.radius, old[id]?.radius)
        }
        do {
            _ = try await session.commitCanvasShiftDrag(drag, translation: .init(x: 0, y: 60))
            XCTFail("A committed gesture must become stale")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testMultipleSelectionUsesRotationAndDoesNotMoveTheRestOfTheChain() async throws {
        let original = try archive()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let initial = try await session.selectGraph(nodes: ["joint", "tip"], edges: [])
        let projection = CanvasProjection(bounds: .init(nodes: initial.nodes), plane: .front, width: 400, height: 400)
        let drag = try CanvasShiftDrag(anchorID: "tip", snapshot: initial, projection: projection)
        XCTAssertTrue(try drag.updates(by: .init(x: 0, y: 60)).isEmpty)
        let result = try await session.commitCanvasShiftDrag(drag, translation: .init(x: 90, y: 60))
        let joint = try result.document.node(id: "joint").position
        let tip = try result.document.node(id: "tip").position
        XCTAssertEqual(joint, .init(x: 1.5, y: -0.5, z: 0.25))
        XCTAssertEqual(tip, .init(x: 1.5, y: 0.5, z: 0.5))
        XCTAssertEqual(try result.document.node(id: "root"), try original.node(id: "root"))
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
    }

    func testExplicitEndpointTargetMatchesPointerResultAndRejectsStaleDraft() async throws {
        let original = try archive()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let snapshot = try await session.select("tip")
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 400, height: 400)
        let target = try XCTUnwrap(EndpointIKTarget(endpointID: "tip", snapshot: snapshot))
        let shift = try CanvasShiftDrag(anchorID: "tip", snapshot: snapshot, projection: projection)
        let translation = CanvasPoint(x: -30, y: -60)
        let destination = projection.moving(target.endpointPosition, by: translation)
        let expected = try shift.updates(by: translation).map(\.value)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(try target.updates(toward: destination).map(\.value), expected)

        let result = try await session.bendEndpoint(target, toward: destination)
        XCTAssertTrue(result.canUndo)
        XCTAssertEqual(result.selectedID, "tip")
        do {
            _ = try await session.bendEndpoint(target, toward: destination)
            XCTFail("A draft from before the committed bend must be stale")
        } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
    }

    func testLockedAxisOutsideBoundsIsIgnoredButNonfiniteInputStillRejects() async throws {
        let original = try archive()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let snapshot = try await session.setLock(.x, isLocked: true)
        let target = try XCTUnwrap(EndpointIKTarget(endpointID: "tip", snapshot: snapshot))
        let masked = try target.updates(toward: .init(x: 2_000_000, y: 1, z: 0.5))
        let bounded = try target.updates(toward: .init(x: 2, y: 1, z: 0.5))
        XCTAssertFalse(masked.isEmpty)
        XCTAssertEqual(masked.map(\.value), bounded.map(\.value))
        XCTAssertThrowsError(try target.updates(toward: .init(x: .nan, y: 1, z: 0.5)))
        XCTAssertThrowsError(try target.updates(toward: .init(x: 2, y: 2_000_000, z: 0.5)))
    }

}
