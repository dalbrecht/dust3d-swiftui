import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EditorStateTests: XCTestCase {
    private func document(locked: Bool = false, visible: Bool = true, edge: String? = nil, unassigned: Bool = false)
        throws -> Dust3DDocument
    {
        let xml = """
            <canvas><nodes>
            <node id="a" partId="p" name="Tip" x="0" y="0" z="0.25" radius="0.1"/>
            <node id="b" partId="p" x="1" y="0.5" z="0.75" radius="0.2"/>
            </nodes><parts><part id="p" locked="\(locked)" visible="\(visible)"/></parts>
            <edges>\(edge ?? "<edge id='e' from='a' to='b'/>")</edges></canvas>
            """
        let model = Data((unassigned ? xml.replacingOccurrences(of: " partId=\"p\"", with: "") : xml).utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let bytes =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        return try Dust3DDocument(data: bytes)
    }

    func testContentsAndSelectionAreStable() throws {
        var state = try EditorState(document: document())
        XCTAssertEqual(state.snapshot.nodes.map(\.id), ["a", "b"])
        XCTAssertEqual(state.snapshot.nodes.first?.title, "Tip")
        XCTAssertEqual(state.snapshot.edges.first?.fromID, "a")
        XCTAssertEqual(state.snapshot.edges.first?.toID, "b")
        XCTAssertNil(state.snapshot.selectedID)
        try state.select("a")
        XCTAssertEqual(state.snapshot.selectedNode?.id, "a")
        XCTAssertThrowsError(try state.select("missing"))
        XCTAssertEqual(state.snapshot.selectedID, "a")
        try state.select(nil)
        XCTAssertNil(state.snapshot.selectedNode)
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertFalse(state.snapshot.canRedo)
    }

    func testMovementRadiusAndUndoPreserveDocument() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.edit(id: "a", position: .init(x: 2, y: 3, z: 4), radius: 0.5)
        XCTAssertEqual(state.snapshot.selectedID, "a")
        XCTAssertEqual(state.snapshot.selectedNode?.value.radius, 0.5)
        XCTAssertEqual(state.snapshot.documentRevision, 1)
        XCTAssertTrue(state.snapshot.canUndo)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertTrue(state.snapshot.canRedo)
        try state.redo()
        XCTAssertEqual(state.snapshot.selectedNode?.value.position.x, 2)
        XCTAssertEqual(state.snapshot.documentRevision, 3)
        try state.redo()
        XCTAssertEqual(state.snapshot.documentRevision, 3)
    }

    func testNoOpAndInvalidCommandsAreAtomic() throws {
        var state = try EditorState(document: document())
        let original = state.snapshot.document.encoded()
        try state.undo()
        try state.edit(id: "a", position: .init(x: 0, y: 0, z: 0.25), radius: 0.1)
        XCTAssertEqual(state.snapshot.documentRevision, 0)
        XCTAssertThrowsError(try state.edit(id: "missing", position: .init(x: 0, y: 0, z: 0), radius: 1))
        XCTAssertThrowsError(try state.edit(id: "b", position: .init(x: .infinity, y: 0, z: 0), radius: 1))
        XCTAssertEqual(state.snapshot.selectedID, "a")
        XCTAssertEqual(state.snapshot.document.encoded(), original)
    }

    func testLockedAndHiddenPartsCannotBeEdited() throws {
        for input in [try document(locked: true), try document(visible: false)] {
            var state = try EditorState(document: input)
            try state.select("a")
            XCTAssertFalse(try XCTUnwrap(state.snapshot.selectedNode).isEditable)
            XCTAssertThrowsError(try state.edit(id: "a", position: .init(x: 1, y: 2, z: 3), radius: 1))
            XCTAssertEqual(state.snapshot.document.encoded(), input.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
            XCTAssertThrowsError(try state.apply([.setNode(id: "a", position: .init(x: 1, y: 2, z: 3), radius: 1)]))
        }
    }

    func testInvalidEdgesAreRejectedAndBlankDocumentIsValid() throws {
        XCTAssertThrowsError(try EditorState(document: document(edge: "<edge id='e' from='a' to='missing'/>")))
        let blank = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        XCTAssertTrue(try EditorState(document: blank).snapshot.nodes.isEmpty)
        XCTAssertTrue(try blank.editorContents().edges.isEmpty)
    }

    func testProjectionDragUsesCorrectAxesAndFitsEmptyBounds() throws {
        let nodes = try document().editorContents().nodes
        let bounds = CanvasBounds(nodes: nodes)
        for plane in [EditingPlane.front, .side] {
            let projection = CanvasProjection(bounds: bounds, plane: plane, width: 800, height: 600)
            let node = try XCTUnwrap(nodes.first).value
            let before = projection.point(for: node.position)
            let moved = projection.moving(node.position, by: CanvasPoint(x: 40, y: -20))
            let after = projection.point(for: moved)
            XCTAssertEqual(after.x - before.x, 40, accuracy: 0.0001)
            XCTAssertEqual(after.y - before.y, -20, accuracy: 0.0001)
            if plane == .front {
                XCTAssertEqual(moved.z, node.position.z)
            } else {
                XCTAssertEqual(moved.x, node.position.x)
            }
        }
        let empty = CanvasProjection(bounds: CanvasBounds(nodes: []), plane: .front, width: 0, height: 0)
        XCTAssertTrue(empty.point(for: .init(x: 0, y: 0, z: 0)).x.isFinite)
        XCTAssertGreaterThan(empty.scale, 0)
    }

    @MainActor func testActorSessionRoutesCommandsAndRejectsMissingDocument() async throws {
        let session = EditorSession()
        do {
            _ = try await session.select("a")
            XCTFail("Missing document accepted")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        let loaded = try await session.open(data: document().encoded())
        XCTAssertEqual(loaded.nodes.count, 2)
        let selected = try await session.select("b")
        XCTAssertEqual(selected.selectedID, "b")
        let edited = try await session.edit(id: "b", position: .init(x: 2, y: 3, z: 4), radius: 0.8)
        XCTAssertEqual(edited.selectedNode?.value.radius, 0.8)
        let undone = try await session.undo()
        XCTAssertEqual(undone.selectedNode?.value.radius, 0.2)
        let redone = try await session.redo()
        XCTAssertEqual(redone.selectedNode?.value.radius, 0.8)
        do {
            _ = try await session.open(data: Data())
            XCTFail("Invalid archive accepted")
        } catch {}
        let retained = try await session.select("a")
        XCTAssertEqual(retained.document.encoded(), redone.document.encoded())
    }
    @MainActor func testSessionsKeepIndependentSelectionAndUndoHistory() async throws {
        let first = EditorSession()
        let second = EditorSession()
        let data = try document().encoded()
        _ = try await first.open(data: data)
        _ = try await second.open(data: data)
        _ = try await first.edit(id: "a", position: .init(x: 3, y: 4, z: 5), radius: 0.6)
        let untouched = try await second.select("b")
        XCTAssertEqual(untouched.document.encoded(), data)
        XCTAssertFalse(untouched.canUndo)
        let changed = try await first.select("a")
        XCTAssertEqual(changed.selectedNode?.value.radius, 0.6)
        XCTAssertTrue(changed.canUndo)
        _ = try await first.undo()
        let branch = try await first.edit(id: "b", position: .init(x: 2, y: 3, z: 4), radius: 0.9)
        XCTAssertFalse(branch.canRedo)
        XCTAssertEqual(branch.selectedID, "b")
        XCTAssertEqual(untouched.selectedID, "b")
    }

    @MainActor func testCancelledSessionOpenDoesNotReplaceLoadedDocument() async throws {
        let session = EditorSession()
        let data = try document().encoded()
        _ = try await session.open(data: data)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.open(data: Dust3DDocument.emptyArchive())
        }
        do {
            _ = try await operation.value
            XCTFail("Cancelled open accepted")
        } catch is CancellationError {
        }
        let retained = try await session.select("a")
        XCTAssertEqual(retained.document.encoded(), data)
    }

    func testTopologyBatchSelectionAndUndoAreAtomic() throws {
        var state = try EditorState(document: document())
        let original = state.snapshot.document.encoded()
        try state.apply(
            [
                .addNode(id: "c", partID: "p", componentID: nil, position: .init(x: 1, y: 1, z: 1), radius: 0.1),
                .addEdge(id: "f", from: "b", to: "c"),
            ], selecting: "c")
        XCTAssertEqual(state.snapshot.selectedID, "c")
        XCTAssertEqual(state.snapshot.nodes.count, 3)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original)
        XCTAssertNil(state.snapshot.selectedID)
        try state.redo()
        try state.apply([.removeNode(id: "b")])
        XCTAssertTrue(state.snapshot.edges.isEmpty)
        XCTAssertEqual(state.snapshot.nodes.count, 2)
        let before = state.snapshot.document.encoded()
        XCTAssertThrowsError(try state.apply([.removeNode(id: "a")], selecting: "missing"))
        XCTAssertEqual(state.snapshot.document.encoded(), before)
        try state.apply([])
        XCTAssertEqual(state.snapshot.document.encoded(), before)
    }

    @MainActor func testActorRoutesTopologyBatch() async throws {
        let session = EditorSession()
        _ = try await session.open(data: document().encoded())
        let removed = try await session.apply([.removeEdge(id: "e")])
        XCTAssertTrue(removed.edges.isEmpty)
        let moved = try await session.apply([.setNode(id: "a", position: .init(x: 1, y: 2, z: 3), radius: 0.5)])
        XCTAssertEqual(moved.nodes.first?.value.radius, 0.5)
    }

    func testConnectionTargetsExcludeNeighborsAndReadonlyNodes() throws {
        var state = try EditorState(document: document())
        XCTAssertTrue(state.snapshot.connectionTargets.isEmpty)
        try state.select("a")
        XCTAssertTrue(state.snapshot.connectionTargets.isEmpty)
        try state.apply([
            .addNode(id: "c", partID: "p", componentID: nil, position: .init(x: 0, y: 1, z: 0), radius: 0.1),
            .addNode(id: "d", partID: "p", componentID: nil, position: .init(x: 0, y: 2, z: 0), radius: 0.1),
            .addEdge(id: "other", from: "c", to: "d"),
            .addNode(
                id: "foreign", partID: "q", componentID: "component-q", position: .init(x: 0, y: 0, z: 0), radius: 0.1),
        ])
        XCTAssertEqual(state.snapshot.connectionTargets.map(\.id), ["c", "d", "foreign"])
        try state.select("b")
        XCTAssertEqual(state.snapshot.connectionTargets.map(\.id), ["c", "d", "foreign"])
        var locked = try EditorState(document: document(locked: true))
        try locked.select("a")
        XCTAssertTrue(locked.snapshot.connectionTargets.isEmpty)
        XCTAssertFalse(locked.snapshot.canAddNode)
        var unassigned = try EditorState(document: document(unassigned: true))
        // Unassigned legacy nodes must still attempt generation and surface diagnostics, rather than look disabled.
        XCTAssertTrue(unassigned.snapshot.hasEnabledGeometry)
        try unassigned.select("a")
        XCTAssertTrue(unassigned.snapshot.connectionTargets.isEmpty)
        XCTAssertTrue(unassigned.snapshot.canAddNode)
    }

}
