import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EditorSelectionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='retain'><nodes><node id='a' partId='p' x='0' y='1' z='2' radius='0.1' future='keep'/><node id='b' partId='p' x='1' y='2' z='3' radius='0.2'/><node id='c' partId='q' x='2' y='3' z='4' radius='0.3'/></nodes><edges><edge id='e' from='a' to='b' partId='p'/></edges><parts><part id='p'/><part id='q' locked='true'/></parts></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='2'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255]))
    }

    func testSelectionIsAtomicTransientAndOrderedByDocument() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.select(["b", "a"])
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b"])
        XCTAssertEqual(state.snapshot.selectedNodes.map(\.id), ["a", "b"])
        XCTAssertEqual(state.snapshot.selectedID, "a")
        XCTAssertTrue(state.snapshot.connectionTargets.isEmpty)
        XCTAssertEqual(state.snapshot.documentRevision, 0)
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertThrowsError(try state.select(["missing", "a"]))
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b"])
        try state.toggleSelection("a")
        XCTAssertEqual(state.snapshot.selectedID, "b")
        try state.toggleSelection("c")
        XCTAssertEqual(state.snapshot.selectedIDs, ["b", "c"])
        XCTAssertThrowsError(try state.toggleSelection("missing"))
        try state.select(nil)
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        state.selectAll()
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c"])
    }

    func testGroupMovementPreservesOffsetsLocksAssetsAndOneUndoStep() throws {
        let original = try document()
        var state = try EditorState(document: original)
        state.selectAll()
        state.setLock(.x, isLocked: true)
        try state.moveSelection(by: .init(x: 10, y: 2, z: -1))
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: 0, y: 3, z: 1))
        XCTAssertEqual(try state.snapshot.document.node(id: "b").position, .init(x: 1, y: 4, z: 2))
        XCTAssertEqual(try state.snapshot.document.node(id: "c"), try original.node(id: "c"))
        XCTAssertEqual(state.snapshot.document.asset(named: "opaque"), Data([0, 255]))
        let xml = try XMLDocument(data: state.snapshot.document.modelXML)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//node[@id='a']").first as? XMLElement)?.attribute(forName: "future")?
                .stringValue, "keep")
        let edited = state.snapshot.document.encoded()
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c"])
        try state.redo()
        XCTAssertEqual(state.snapshot.document.encoded(), edited)
        let revision = state.snapshot.documentRevision
        XCTAssertThrowsError(try state.moveSelection(by: .init(x: .nan, y: 0, z: 0)))
        XCTAssertThrowsError(try state.moveSelection(by: .init(x: 0, y: 1_000_000, z: 0)))
        XCTAssertEqual(state.snapshot.document.encoded(), edited)
        XCTAssertEqual(state.snapshot.documentRevision, revision)
    }

    func testEmptyReadOnlyAndLockedMovementPreservesRedo() throws {
        var state = try EditorState(document: document())
        try state.moveSelection(by: .init(x: 1, y: 2, z: 3))
        try state.deleteSelection()
        try state.select("a")
        try state.moveSelection(by: .init(x: 1, y: 0, z: 0))
        try state.undo()
        for lock in EditingConstraint.allCases { state.setLock(lock, isLocked: true) }
        try state.moveSelection(by: .init(x: 1, y: 2, z: 3))
        XCTAssertTrue(state.snapshot.canRedo)
        try state.select("c")
        try state.moveSelection(by: .init(x: 1, y: 2, z: 3))
        try state.deleteSelection()
        XCTAssertTrue(state.snapshot.canRedo)
        XCTAssertEqual(state.snapshot.selectedID, "c")
    }

    func testDeletionPrunesSelectionAndRestoresExactArchiveWithUndo() throws {
        let original = try document()
        var state = try EditorState(document: original)
        state.selectAll()
        try state.deleteSelection()
        XCTAssertEqual(state.snapshot.nodes.map(\.id), ["c"])
        XCTAssertEqual(state.snapshot.selectedIDs, ["c"])
        XCTAssertEqual(state.snapshot.selectedID, "c")
        XCTAssertTrue(state.snapshot.edges.isEmpty)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        try state.select(["a", "b"])
        try state.deleteSelection()
        XCTAssertNil(state.snapshot.selectedID)
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
    }

    func testBulkNodeUpdatesRejectDuplicatesAndPreserveNoOpBytes() throws {
        let original = try document()
        let a = NodeUpdate(id: "a", value: try original.node(id: "a"))
        XCTAssertEqual(try original.applying(.setNodes([a])).encoded(), original.encoded())
        XCTAssertThrowsError(try original.applying(.setNodes([a, a])))
        XCTAssertThrowsError(try original.applying(.setNodes([.init(id: "missing", value: a.value)])))
        XCTAssertThrowsError(
            try original.applying(.setNodes([.init(id: "a", value: .init(position: a.value.position, radius: -1))])))
        var state = try EditorState(document: original)
        try state.apply([
            .setNodes([.init(id: "a", value: .init(position: .init(x: 1, y: 1, z: 2), radius: 0.1))]), .setNodes([a]),
        ])
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertThrowsError(try state.apply([.setNodes([.init(id: "c", value: a.value)])]))
    }

    func testDraggingSelectedAnchorMovesGroupAndUnselectedAnchorReplacesSelection() throws {
        var state = try EditorState(document: document())
        try state.select(["a", "b"])
        try state.move(id: "b", to: .init(x: 2, y: 3, z: 4))
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: 1, y: 2, z: 3))
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b"])
        try state.select("b")
        try state.move(id: "a", to: .init(x: 2, y: 3, z: 4))
        XCTAssertEqual(state.snapshot.selectedIDs, ["a"])
        XCTAssertThrowsError(try state.move(id: "missing", to: .init(x: 0, y: 0, z: 0)))
        XCTAssertThrowsError(try state.move(id: "c", to: .init(x: 0, y: 0, z: 0)))
        XCTAssertEqual(state.snapshot.selectedIDs, ["a"])
    }

    func testBulkDeletionValidatesWholeSetAndPreservesEmptyNoOp() throws {
        let original = try document()
        XCTAssertEqual(try original.applying(.removeNodes([])).encoded(), original.encoded())
        XCTAssertThrowsError(try original.applying(.removeNodes(["a", "a"])))
        XCTAssertThrowsError(try original.applying(.removeNodes(["a", "missing"])))
        XCTAssertThrowsError(try original.applying(.removeNodes(["a", "c"])))
        let deleted = try original.applying(.removeNodes(["a", "b"]))
        XCTAssertEqual(try deleted.editorContents().nodes.map(\.id), ["c"])
        XCTAssertEqual(deleted.asset(named: "opaque"), Data([0, 255]))
    }

    @MainActor func testSessionSelectionAndGroupCommands() async throws {
        let session = EditorSession()
        _ = try await session.open(data: document().encoded())
        _ = try await session.select(Set(["a", "b"]))
        _ = try await session.toggleSelection("c")
        let all = try await session.selectAll()
        XCTAssertEqual(all.selectedIDs.count, 3)
        _ = try await session.move(id: "a", to: .init(x: 0, y: 1, z: 2))
        let moved = try await session.moveSelection(by: .init(x: 1, y: 0, z: 0))
        XCTAssertEqual(try moved.document.node(id: "b").position.x, 2)
        let deleted = try await session.deleteSelection()
        XCTAssertEqual(deleted.nodes.count, 1)
    }
}
