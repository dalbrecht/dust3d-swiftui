import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor
final class EdgeStrokeDragTests: XCTestCase {
    private func source(locked: Bool = false) throws -> Data {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='2' y='2' z='2' radius='.1'/>
                <node id='c' partId='q' x='0' y='2' z='0' radius='.1'/>
                <node id='d' partId='q' x='2' y='0' z='2' radius='.1'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b'/>
                <edge id='cd' partId='q' from='c' to='d'/></edges>
                <parts><part id='p'/><part id='q' locked='\(locked)'/></parts></canvas>
                """.utf8)
        ).encoded()
    }

    private func projection(_ plane: EditingPlane, _ snapshot: EditorSnapshot) -> CanvasProjection {
        .init(bounds: .init(nodes: snapshot.nodes), plane: plane, width: 400, height: 300)
    }

    func testStrokeHitAgreesWithTapAtCrossingAndDoesNotSkipReadOnlyNearestEdge() throws {
        let state = try EditorState(document: Dust3DDocument(data: source(locked: true)))
        let snapshot = state.snapshot
        for plane in [EditingPlane.front, .side] {
            let projection = projection(plane, snapshot)
            let crossing = projection.point(for: .init(x: 1, y: 1, z: 1))
            XCTAssertEqual(projection.edgeID(near: crossing, nodes: snapshot.nodes, edges: snapshot.edges), "ab")
            let drag = try XCTUnwrap(NodeDrag.edgeStroke(at: crossing, snapshot: snapshot, projection: projection))
            XCTAssertEqual(drag.edgeID, "ab")
            XCTAssertTrue(drag.includes("a"))
            XCTAssertTrue(drag.includes("b"))
            XCTAssertFalse(drag.includes("c"))
            let lockedHit = CanvasPoint(x: crossing.x - 3, y: crossing.y + 3)
            XCTAssertEqual(
                projection.edgeID(
                    near: lockedHit, nodes: snapshot.nodes, edges: snapshot.edges.filter { $0.id == "ab" }),
                "ab")
            XCTAssertEqual(projection.edgeID(near: lockedHit, nodes: snapshot.nodes, edges: snapshot.edges), "cd")
            XCTAssertNil(NodeDrag.edgeStroke(at: lockedHit, snapshot: snapshot, projection: projection))
            let blank = projection.point(for: .init(x: 1, y: 0, z: 1))
            XCTAssertNil(NodeDrag.edgeStroke(at: blank, snapshot: snapshot, projection: projection))
        }
    }

    func testUnselectedStrokeMovesOnlyItsEndpointsAndSelectsEdgeInOneUndo() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original)
        let before = try await session.select("c")
        let projection = projection(.side, before)
        let hit = projection.point(for: .init(x: 0.5, y: 0.5, z: 0.5))
        let drag = try XCTUnwrap(NodeDrag.edgeStroke(at: hit, snapshot: before, projection: projection))
        let translation = CanvasPoint(x: 12, y: -9)
        let changed = try await session.commitNodeDrag(drag, translation: translation)
        XCTAssertEqual(changed.selectedIDs, [])
        XCTAssertEqual(changed.selectedEdgeIDs, ["ab"])
        try assertMovement(
            before: before, after: changed, moving: ["a", "b"], drag: drag, translation: translation)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original)
        XCTAssertFalse(undone.canUndo)
    }

    func testSelectedStrokeKeepsMixedPicksAndMovesDeduplicatedNodesWithLocks() async throws {
        let session = EditorSession()
        _ = try await session.open(data: source(locked: true))
        _ = try await session.setLock(.y, isLocked: true)
        let before = try await session.selectGraph(nodes: ["b", "c"], edges: ["ab"])
        let projection = projection(.front, before)
        let hit = projection.point(for: .init(x: 0.5, y: 0.5, z: 0.5))
        let drag = try XCTUnwrap(NodeDrag.edgeStroke(at: hit, snapshot: before, projection: projection))
        let translation = CanvasPoint(x: 12, y: -9)
        let changed = try await session.commitNodeDrag(drag, translation: translation)
        XCTAssertEqual(changed.selectedIDs, before.selectedIDs)
        XCTAssertEqual(changed.selectedEdgeIDs, before.selectedEdgeIDs)
        try assertMovement(
            before: before, after: changed, moving: ["a", "b"], drag: drag, translation: translation)
        XCTAssertEqual(changed.nodes.map { $0.value.position.y }, before.nodes.map { $0.value.position.y })
    }

    func testFailedReplacementRejectsCapturedStroke() async throws {
        let original = try source()
        let session = EditorSession()
        let before = try await session.open(data: original)
        let projection = projection(.front, before)
        let hit = projection.point(for: .init(x: 0.5, y: 0.5, z: 0.5))
        let drag = try XCTUnwrap(NodeDrag.edgeStroke(at: hit, snapshot: before, projection: projection))
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid archive opened")
        } catch {}
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 12, y: 8))
            XCTFail("Failed replacement retained a writable stroke")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        let retained = try await session.animationSnapshot().editor
        XCTAssertEqual(retained.document.encoded(), original)
        XCTAssertFalse(retained.canUndo)
    }

    private func assertMovement(
        before: EditorSnapshot, after: EditorSnapshot, moving: Set<String>, drag: NodeDrag, translation: CanvasPoint
    ) throws {
        for node in before.nodes {
            let result = try XCTUnwrap(after.nodes.first { $0.id == node.id }).value.position
            let expected =
                moving.contains(node.id)
                ? drag.position(of: node.value.position, by: translation) : node.value.position
            XCTAssertEqual(result.x, expected.x, accuracy: 1e-12)
            XCTAssertEqual(result.y, expected.y, accuracy: 1e-12)
            XCTAssertEqual(result.z, expected.z, accuracy: 1e-12)
        }
    }
}
