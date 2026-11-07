import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class CanvasGraphHoverTests: XCTestCase {
    private func makeState(partAttributes: String = "") throws -> EditorState {
        let xml = """
            <canvas><nodes>
            <node id='a' partId='p' x='1' y='2' z='4' radius='0.1'/>
            <node id='b' partId='p' x='5' y='4' z='6' radius='0.1'/>
            </nodes><edges><edge id='ab' partId='p' from='a' to='b'/></edges>
            <parts><part id='p' \(partAttributes)/></parts></canvas>
            """
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        return try EditorState(document: document)
    }

    func testProjectedHoverReturnsTheSameNodeAndEdgeIDsInBothProfiles() throws {
        let snapshot = try makeState().snapshot
        let bounds = CanvasBounds(nodes: snapshot.nodes)
        var cache = CanvasGraphHover.Cache()
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(bounds: bounds, plane: plane, width: 480, height: 360)
            let endpoint = projection.point(for: .init(x: 1, y: 2, z: 4))
            let midpoint = projection.point(for: .init(x: 3, y: 3, z: 5))
            XCTAssertEqual(
                cache.hit(at: endpoint, projection: projection, snapshot: snapshot), .node("a"),
                "A node wins when it overlaps an edge endpoint in \(plane)")
            XCTAssertEqual(
                cache.hit(at: midpoint, projection: projection, snapshot: snapshot), .edge("ab"))
            XCTAssertNil(cache.hit(at: .init(x: 1, y: 1), projection: projection, snapshot: snapshot))
        }
    }

    func testHiddenNodesAndTheirEdgesDoNotHover() throws {
        let visible = try makeState().snapshot
        let hidden = try makeState(partAttributes: "visible='false'").snapshot
        let projection = CanvasProjection(
            bounds: CanvasBounds(nodes: visible.nodes), plane: .front, width: 480, height: 360)
        XCTAssertFalse(hidden.nodes.contains(where: \.isVisible))
        var cache = CanvasGraphHover.Cache()
        let endpoint = projection.point(for: .init(x: 1, y: 2, z: 4))
        let midpoint = projection.point(for: .init(x: 3, y: 3, z: 5))
        XCTAssertNil(cache.hit(at: endpoint, projection: projection, snapshot: hidden))
        XCTAssertNil(cache.hit(at: midpoint, projection: projection, snapshot: hidden))
    }

    func testCacheReusesSelectionOnlyGeometryAndRebuildsForRevisionAndProjection() throws {
        var state = try makeState()
        let original = state.snapshot
        let bounds = CanvasBounds(nodes: original.nodes)
        let front = CanvasProjection(bounds: bounds, plane: .front, width: 480, height: 360)
        let endpoint = front.point(for: .init(x: 1, y: 2, z: 4))
        let midpoint = front.point(for: .init(x: 3, y: 3, z: 5))
        var cache = CanvasGraphHover.Cache()

        XCTAssertEqual(cache.hit(at: endpoint, projection: front, snapshot: original), .node("a"))
        let originalEntry = try XCTUnwrap(cache.entry)
        XCTAssertEqual(cache.hit(at: midpoint, projection: front, snapshot: original), .edge("ab"))
        XCTAssertTrue(cache.entry === originalEntry)

        try state.select("b")
        XCTAssertEqual(state.snapshot.documentRevision, original.documentRevision)
        XCTAssertNotEqual(state.snapshot.selectionRevision, original.selectionRevision)
        XCTAssertEqual(cache.hit(at: endpoint, projection: front, snapshot: state.snapshot), .node("a"))
        XCTAssertTrue(cache.entry === originalEntry)

        let movedPosition = NodePosition(x: 3, y: 1, z: 4)
        try state.edit(id: "a", position: movedPosition, radius: 0.1)
        XCTAssertNotEqual(state.snapshot.documentRevision, original.documentRevision)
        let movedEndpoint = front.point(for: movedPosition)
        XCTAssertEqual(cache.hit(at: movedEndpoint, projection: front, snapshot: state.snapshot), .node("a"))
        XCTAssertNil(cache.hit(at: endpoint, projection: front, snapshot: state.snapshot))
        let editedEntry = try XCTUnwrap(cache.entry)
        XCTAssertFalse(editedEntry === originalEntry)

        let side = CanvasProjection(bounds: bounds, plane: .side, width: 300, height: 360)
        XCTAssertEqual(
            cache.hit(at: side.point(for: movedPosition), projection: side, snapshot: state.snapshot), .node("a"))
        XCTAssertFalse(cache.entry === editedEntry)
    }
}
