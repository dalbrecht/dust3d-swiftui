import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class NodeDragTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "a", partID: "p", componentID: "c",
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
    }

    func testCommitUsesCapturedProjectionAndExactUndoRedo() async throws {
        let original = try document().encoded()
        let session = EditorSession()
        let snapshot = try await session.open(data: original)
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 400, height: 400)
        let drag = try NodeDrag(snapshot: snapshot, anchorID: "a", projection: projection)
        let translation = CanvasPoint(x: 20, y: 10)
        let committed = try await session.commitNodeDrag(drag, translation: translation)
        XCTAssertEqual(committed.nodes.first?.value.position, drag.position(by: translation))
        XCTAssertNotEqual(committed.document.encoded(), original)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original)
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), committed.document.encoded())
    }

    func testInterveningSelectionAndReplacementRejectLateCommit() async throws {
        let session = EditorSession()
        let original = try document().encoded()
        let snapshot = try await session.open(data: original)
        let drag = try NodeDrag(
            snapshot: snapshot, anchorID: "a",
            projection: .init(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 400, height: 400))
        _ = try await session.select("a")
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 20, y: 0))
            XCTFail("An old selection must not determine a new gesture's group")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        let retained = try await session.open(data: original)
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 20, y: 0))
            XCTFail("A replaced document must reject an old gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        XCTAssertEqual(retained.document.encoded(), original)
        XCTAssertFalse(retained.canUndo)
    }
    func testPreviewGroupsEditableSelectionAndRespectsLocks() throws {
        var document = try document()
        document = try document.applying(
            .addNode(
                id: "b", partID: "p", componentID: nil,
                position: .init(x: 0.7, y: 0.5, z: 0.5), radius: 0.1))
        var state = try EditorState(document: document)
        try state.select(Set(["a", "b"]))
        state.setLock(.x, isLocked: true)
        let snapshot = state.snapshot
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 400, height: 400)
        let drag = try NodeDrag(snapshot: snapshot, anchorID: "a", projection: projection)
        for node in snapshot.nodes {
            let preview = drag.previewPosition(for: node, by: .init(x: 30, y: 20))
            XCTAssertEqual(preview.x, node.value.position.x)
            XCTAssertGreaterThan(preview.y, node.value.position.y)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), document.encoded())
        try state.select("a")
        let single = try NodeDrag(snapshot: state.snapshot, anchorID: "a", projection: projection)
        let other = try XCTUnwrap(state.snapshot.nodes.first { $0.id == "b" })
        XCTAssertEqual(single.previewPosition(for: other, by: .init(x: 20, y: 20)), other.value.position)
        XCTAssertThrowsError(try NodeDrag(snapshot: state.snapshot, anchorID: "missing", projection: projection))
    }

    func testLockEpochAndOtherWindowRejectBaselineAndInvalidTranslationIsAtomic() async throws {
        let source = try document().encoded()
        let session = EditorSession()
        let snapshot = try await session.open(data: source)
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 400, height: 400)
        let drag = try NodeDrag(snapshot: snapshot, anchorID: "a", projection: projection)
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: .nan, y: 0))
            XCTFail("Nonfinite displacement must be rejected")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        _ = try await session.setLock(.x, isLocked: true)
        _ = try await session.setLock(.x, isLocked: false)
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 20, y: 0))
            XCTFail("Restoring locks must not revive an old gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        let other = EditorSession()
        let retained = try await other.open(data: source)
        do {
            _ = try await other.commitNodeDrag(drag, translation: .init(x: 20, y: 0))
            XCTFail("Another window must not accept this gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        XCTAssertEqual(retained.document.encoded(), source)
        XCTAssertFalse(retained.canUndo)
    }

    func testUnselectedAnchorPreviewAndReadOnlyNodes() throws {
        let source = try document()
        let state = try EditorState(document: source)
        let projection = CanvasProjection(
            bounds: .init(nodes: state.snapshot.nodes), plane: .front, width: 400, height: 400)
        let drag = try NodeDrag(snapshot: state.snapshot, anchorID: "a", projection: projection)
        let node = try XCTUnwrap(state.snapshot.nodes.first)
        XCTAssertEqual(drag.previewPosition(for: node, by: .init(x: 20, y: 0)), drag.position(by: .init(x: 20, y: 0)))
        let locked = try EditorState(document: source.applying(.setPartState(id: "p", property: .locked, value: true)))
        let protected = try XCTUnwrap(locked.snapshot.nodes.first)
        XCTAssertEqual(drag.previewPosition(for: protected, by: .init(x: 20, y: 0)), protected.value.position)
        XCTAssertThrowsError(try NodeDrag(snapshot: locked.snapshot, anchorID: "a", projection: projection)) {
            XCTAssertEqual($0 as? EditorError, .readOnlyNode)
        }
    }

}
