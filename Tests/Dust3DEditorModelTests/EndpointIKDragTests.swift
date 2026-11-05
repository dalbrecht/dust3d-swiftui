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
        XCTAssertNil(EndpointIKDrag(endpointID: "root", snapshot: initial, projection: projection))
        XCTAssertNil(EndpointIKDrag(endpointID: "joint", snapshot: initial, projection: projection))
        let drag = try XCTUnwrap(EndpointIKDrag(endpointID: "tip", snapshot: initial, projection: projection))
        let result = try await session.commitEndpointIKDrag(drag, translation: .init(x: -30, y: -60))
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
            _ = try await session.commitEndpointIKDrag(drag, translation: .init(x: 0, y: 60))
            XCTFail("A committed gesture must become stale")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
    }
}
