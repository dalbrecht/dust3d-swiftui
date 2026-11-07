import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class CanvasGraphHoverTests: XCTestCase {
    private func snapshot(partAttributes: String = "") throws -> EditorSnapshot {
        let xml = """
            <canvas><nodes>
            <node id='a' partId='p' x='1' y='2' z='4' radius='0.1'/>
            <node id='b' partId='p' x='5' y='4' z='6' radius='0.1'/>
            </nodes><edges><edge id='ab' partId='p' from='a' to='b'/></edges>
            <parts><part id='p' \(partAttributes)/></parts></canvas>
            """
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        return try EditorState(document: document).snapshot
    }

    func testProjectedHoverReturnsTheSameNodeAndEdgeIDsInBothProfiles() throws {
        let snapshot = try snapshot()
        let bounds = CanvasBounds(nodes: snapshot.nodes)
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(bounds: bounds, plane: plane, width: 480, height: 360)
            let endpoint = projection.point(for: .init(x: 1, y: 2, z: 4))
            let midpoint = projection.point(for: .init(x: 3, y: 3, z: 5))
            XCTAssertEqual(
                CanvasGraphHover.hit(at: endpoint, projection: projection, snapshot: snapshot), .node("a"),
                "A node wins when it overlaps an edge endpoint in \(plane)")
            XCTAssertEqual(
                CanvasGraphHover.hit(at: midpoint, projection: projection, snapshot: snapshot), .edge("ab"))
            XCTAssertNil(CanvasGraphHover.hit(at: .init(x: 1, y: 1), projection: projection, snapshot: snapshot))
        }
    }

    func testHiddenNodesAndTheirEdgesDoNotHover() throws {
        let visible = try snapshot()
        let hidden = try snapshot(partAttributes: "visible='false'")
        let projection = CanvasProjection(
            bounds: CanvasBounds(nodes: visible.nodes), plane: .front, width: 480, height: 360)
        XCTAssertFalse(hidden.nodes.contains(where: \.isVisible))
        let endpoint = projection.point(for: .init(x: 1, y: 2, z: 4))
        let midpoint = projection.point(for: .init(x: 3, y: 3, z: 5))
        XCTAssertNil(CanvasGraphHover.hit(at: endpoint, projection: projection, snapshot: hidden))
        XCTAssertNil(CanvasGraphHover.hit(at: midpoint, projection: projection, snapshot: hidden))
    }
}
