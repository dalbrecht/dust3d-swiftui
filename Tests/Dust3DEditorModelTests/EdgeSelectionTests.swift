import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EdgeSelectionTests: XCTestCase {
    private func document(locked: Bool = false, visible: Bool = true) throws -> Dust3DDocument {
        let model = Data(
            """
            <canvas><nodes>
            <node id="a" partId="p" x="0" y="0" z="0" radius="0.1"/>
            <node id="b" partId="p" x="1" y="0" z="0" radius="0.1"/>
            <node id="c" partId="p" x="0" y="1" z="1" radius="0.1"/>
            </nodes><parts><part id="p" locked="\(locked)" visible="\(visible)" future="keep"/></parts>
            <edges><edge id="e1" partId="p" from="a" to="b" future="retain"/>
            <edge id="e2" partId="p" from="b" to="c"/></edges></canvas>
            """.utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }

    func testEdgeSelectionIsTransientAndExclusiveWithNodes() throws {
        let original = try document()
        var state = try EditorState(document: original)
        XCTAssertNil(state.snapshot.selectedEdge)
        XCTAssertFalse(state.snapshot.canEditSelectedEdge)
        try state.select("a")
        try state.selectEdge("e1")
        XCTAssertEqual(state.snapshot.selectedEdgeID, "e1")
        XCTAssertEqual(state.snapshot.selectedEdge?.fromID, "a")
        XCTAssertTrue(state.snapshot.canEditSelectedEdge)
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertNil(state.snapshot.selectedID)
        XCTAssertFalse(state.snapshot.canAddNode)
        XCTAssertFalse(state.snapshot.canCopyNodes)
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.documentRevision, 0)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertThrowsError(try state.selectEdge("missing"))
        XCTAssertEqual(state.snapshot.selectedEdgeID, "e1")
        try state.select("b")
        XCTAssertNil(state.snapshot.selectedEdgeID)
        try state.selectEdge("e1")
        state.selectAll()
        XCTAssertNil(state.snapshot.selectedEdgeID)
        try state.selectEdge("e1")
        try state.selectEdge(nil)
        XCTAssertNil(state.snapshot.selectedEdgeID)
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
    }

    func testReadonlyEdgeCanBeInspectedWithoutMutation() throws {
        var state = try EditorState(document: document(locked: true))
        try state.selectEdge("e1")
        XCTAssertNotNil(state.snapshot.selectedEdge)
        XCTAssertFalse(state.snapshot.canEditSelectedEdge)
        XCTAssertThrowsError(try state.apply([.reverseEdges(["e1"])]))
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.selectedEdgeID, "e1")
    }

    func testReversalRetainsEdgeSelectionAndDeletionPrunesIt() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.selectEdge("e1")
        try state.apply([.reverseEdges(["e1"])])
        XCTAssertEqual(state.snapshot.selectedEdge?.fromID, "b")
        XCTAssertTrue(String(decoding: state.snapshot.document.modelXML, as: UTF8.self).contains("future=\"retain\""))
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertEqual(state.snapshot.selectedEdge?.fromID, "a")
        try state.apply([.removeEdge(id: "e1")])
        XCTAssertNil(state.snapshot.selectedEdgeID)
        try state.undo()
        XCTAssertNil(state.snapshot.selectedEdgeID)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
    }

    func testActorSelectionAndDeletionUseOneUndoTransaction() async throws {
        let original = try document()
        let session = EditorSession()
        do {
            _ = try await session.selectEdge("e1")
            XCTFail("A document is required")
        } catch {}
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectEdge("e1")
        XCTAssertFalse(selected.canUndo)
        let deleted = try await session.deleteSelection()
        XCTAssertEqual(deleted.edges.count, 1)
        XCTAssertEqual(deleted.nodes.count, 3)
        XCTAssertNil(deleted.selectedEdgeID)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
        XCTAssertFalse(restored.canUndo)
        XCTAssertTrue(restored.canRedo)
        _ = try await session.open(data: document(locked: true).encoded())
        _ = try await session.selectEdge("e1")
        do {
            _ = try await session.deleteSelection()
            XCTFail("Readonly edges must reject deletion")
        } catch {}
        let retained = try await session.selectEdge("e1")
        XCTAssertFalse(retained.canUndo)
        XCTAssertEqual(retained.edges.count, 2)
    }

    func testLowLevelSelectionDeletionAlsoRecognizesEdges() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.selectEdge("e1")
        try state.deleteSelection()
        XCTAssertEqual(state.snapshot.nodes.count, 3)
        XCTAssertEqual(state.snapshot.edges.count, 1)
        XCTAssertNil(state.snapshot.selectedEdgeID)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        var locked = try EditorState(document: document(locked: true))
        try locked.selectEdge("e1")
        XCTAssertThrowsError(try locked.deleteSelection())
        XCTAssertEqual(locked.snapshot.selectedEdgeID, "e1")
        XCTAssertFalse(locked.snapshot.canUndo)
    }

    func testNearestVisibleEdgePickingInBothPlanes() throws {
        let contents = try document().editorContents()
        let bounds = CanvasBounds(nodes: contents.nodes)
        let front = CanvasProjection(bounds: bounds, plane: .front, width: 600, height: 600)
        let middle = front.point(for: .init(x: 0.5, y: 0, z: 0))
        XCTAssertEqual(front.edgeID(near: middle, nodes: contents.nodes, edges: contents.edges), "e1")
        XCTAssertEqual(
            front.edgeID(near: .init(x: middle.x, y: middle.y + 8), nodes: contents.nodes, edges: contents.edges), "e1")
        XCTAssertNil(
            front.edgeID(near: .init(x: middle.x, y: middle.y + 9), nodes: contents.nodes, edges: contents.edges))
        XCTAssertNil(
            front.edgeID(
                near: front.point(for: .init(x: 1.2, y: 0, z: 0)), nodes: contents.nodes, edges: [contents.edges[0]]))
        let side = CanvasProjection(bounds: bounds, plane: .side, width: 600, height: 600)
        XCTAssertEqual(
            side.edgeID(
                near: side.point(for: .init(x: 0.5, y: 0.5, z: 0.5)), nodes: contents.nodes, edges: contents.edges),
            "e2")
        XCTAssertNil(
            side.edgeID(
                near: side.point(for: .init(x: 0, y: 0, z: 0)), nodes: contents.nodes, edges: [contents.edges[0]]))
        let junction = front.point(for: contents.nodes[1].value.position)
        XCTAssertEqual(front.edgeID(near: junction, nodes: contents.nodes, edges: contents.edges), "e1")
    }

    func testInvalidHiddenAndMissingEndpointPickingReturnsNothing() throws {
        let contents = try document().editorContents()
        let projection = CanvasProjection(
            bounds: CanvasBounds(nodes: contents.nodes), plane: .front, width: 600, height: 600)
        let point = projection.point(for: .init(x: 0.5, y: 0, z: 0))
        XCTAssertNil(projection.edgeID(near: .init(x: .nan, y: 0), nodes: contents.nodes, edges: contents.edges))
        XCTAssertNil(projection.edgeID(near: point, nodes: contents.nodes, edges: contents.edges, tolerance: -1))
        XCTAssertNil(projection.edgeID(near: point, nodes: contents.nodes, edges: contents.edges, tolerance: .infinity))
        XCTAssertNil(projection.edgeID(near: point, nodes: Array(contents.nodes.prefix(1)), edges: contents.edges))
        let hidden = try document(visible: false).editorContents()
        XCTAssertNil(projection.edgeID(near: point, nodes: hidden.nodes, edges: hidden.edges))
    }
}
