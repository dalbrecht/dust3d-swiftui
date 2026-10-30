import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class NodeDragTests: XCTestCase {
    private func data() -> Data {
        let model = Data(
            "<canvas><nodes><node id='a' partId='p' x='0' y='1' z='2' radius='.1'/><node id='b' partId='p' x='1' y='2' z='3' radius='.2'/></nodes><edges><edge id='e' partId='p' from='a' to='b'/></edges><parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
    }

    func testStaleDragCannotMoveReplacementOrChangedSelectionAndLocks() async throws {
        let session = EditorSession()
        let original = data()
        var snapshot = try await session.open(data: original)
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        var drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        snapshot = try await session.open(data: original)
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 40, y: 20))
            XCTFail("Replacement must invalidate the gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        _ = try await session.select("b")
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 40, y: 20))
            XCTFail("Selection change must invalidate the gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        snapshot = try await session.select(nil)
        drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        _ = try await session.setLock(.x, isLocked: true)
        _ = try await session.setLock(.x, isLocked: false)
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 40, y: 20))
            XCTFail("Lock cycle must invalidate the gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        let unchanged = try await session.apply([])
        XCTAssertEqual(unchanged.document.encoded(), original)
        XCTAssertFalse(unchanged.canUndo)
    }

    func testInvalidAnchorAndDisplacementAreRejectedWithoutHistory() async throws {
        let session = EditorSession()
        let original = data()
        let snapshot = try await session.open(data: original)
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        XCTAssertThrowsError(try NodeDrag(anchorID: "missing", snapshot: snapshot, projection: projection))
        let drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        for translation in [CanvasPoint(x: .nan, y: 0), .init(x: .infinity, y: 0), .init(x: 1e12, y: 0)] {
            do {
                _ = try await session.commitNodeDrag(drag, translation: translation)
                XCTFail("Invalid displacement must not commit")
            } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        }
        let locked = try await session.setLock(.x, isLocked: true)
        let lockedDrag = try NodeDrag(anchorID: "a", snapshot: locked, projection: projection)
        do {
            _ = try await session.commitNodeDrag(lockedDrag, translation: .init(x: .nan, y: 0))
            XCTFail("A locked axis must not hide invalid input")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let noop = try await session.commitNodeDrag(lockedDrag, translation: .init(x: 0, y: 0))
        XCTAssertEqual(noop.document.encoded(), original)
        XCTAssertFalse(noop.canUndo)
    }

    func testOtherWindowAndChangedDocumentRejectCapturedGesture() async throws {
        let original = data()
        let first = EditorSession()
        let second = EditorSession()
        let snapshot = try await first.open(data: original)
        _ = try await second.open(data: original)
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        let drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        do {
            _ = try await second.commitNodeDrag(drag, translation: .init(x: 10, y: 10))
            XCTFail("Another window must reject the gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        _ = try await first.move(id: "b", to: .init(x: 2, y: 2, z: 3))
        do {
            _ = try await first.commitNodeDrag(drag, translation: .init(x: 10, y: 10))
            XCTFail("An intervening edit must invalidate the gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
    }

    func testSelectionCycleCannotReviveCapturedDrag() async throws {
        let session = EditorSession()
        let original = data()
        let snapshot = try await session.open(data: original)
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        let drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        _ = try await session.select("b")
        _ = try await session.select(nil)
        do {
            _ = try await session.commitNodeDrag(drag, translation: .init(x: 40, y: 20))
            XCTFail("Returning to the previous selection must not revive the gesture")
        } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
        let unchanged = try await session.apply([])
        XCTAssertEqual(unchanged.document.encoded(), original)
        XCTAssertFalse(unchanged.canUndo)
    }

    func testRedundantSelectionDoesNotInvalidateDrag() async throws {
        let session = EditorSession()
        _ = try await session.open(data: data())
        let snapshot = try await session.select("a")
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        let drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        _ = try await session.select("a")
        let moved = try await session.commitNodeDrag(drag, translation: .init(x: 40, y: 20))
        XCTAssertTrue(moved.canUndo)
    }

    func testPartAndSelectAllCyclesInvalidateDragWithoutChangingHistory() async throws {
        let session = EditorSession()
        let original = data()
        var snapshot = try await session.open(data: original)
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        for selection in ["part", "all"] {
            let drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
            if selection == "part" {
                _ = try await session.selectPart("p")
            } else {
                _ = try await session.selectAll()
            }
            snapshot = try await session.select(nil)
            do {
                _ = try await session.commitNodeDrag(drag, translation: .init(x: 40, y: 20))
                XCTFail("A selection cycle must invalidate the gesture")
            } catch { XCTAssertEqual(error as? EditorError, .staleNodeDrag) }
            XCTAssertEqual(snapshot.document.encoded(), original)
            XCTAssertFalse(snapshot.canUndo)
        }
    }

    func testSelectionGenerationTracksExclusiveClearsAndPreservesNoOps() async throws {
        let session = EditorSession()
        let initial = try await session.open(data: data())
        var revision = initial.selectionRevision
        let empty = try await session.selectComponents([])
        XCTAssertEqual(empty.selectionRevision, revision)
        _ = try await session.select("a")
        let clearNode = try await session.selectPart(nil)
        XCTAssertEqual(clearNode.selectionRevision, revision + 2)
        revision = clearNode.selectionRevision
        _ = try await session.selectPart("p")
        let clearPart = try await session.selectComponents([])
        XCTAssertEqual(clearPart.selectionRevision, revision + 2)
        revision = clearPart.selectionRevision
        _ = try await session.selectEdge("e")
        let clearEdge = try await session.selectComponents([])
        XCTAssertEqual(clearEdge.selectionRevision, revision + 2)
        revision = clearEdge.selectionRevision
        _ = try await session.select("a")
        let clearNodes = try await session.selectComponents([])
        XCTAssertEqual(clearNodes.selectionRevision, revision + 2)
        XCTAssertFalse(clearNodes.canUndo)
        XCTAssertEqual(clearNodes.document.encoded(), initial.document.encoded())
    }

    func testValidGroupDragCommitsOnceAndUndoRestoresExactArchive() async throws {
        let session = EditorSession()
        let original = data()
        _ = try await session.open(data: original)
        let snapshot = try await session.select(["a", "b"])
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .side, width: 472, height: 472)
        let drag = try NodeDrag(anchorID: "a", snapshot: snapshot, projection: projection)
        let moved = try await session.commitNodeDrag(drag, translation: .init(x: 40, y: 20))
        XCTAssertTrue(moved.canUndo)
        XCTAssertNotEqual(moved.document.encoded(), original)
        let undo = try await session.undo()
        XCTAssertEqual(undo.document.encoded(), original)
        XCTAssertFalse(undo.canUndo)
    }
}

extension NodeDragTests {
    func testGestureResetAndCompletionOrderingAndCancellation() async throws {
        let session = EditorSession()
        let snapshot = try await session.open(data: data())
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        for resetFirst in [false, true] {
            var lifecycle = NodeDragLifecycle()
            try lifecycle.update(
                anchorID: "a", snapshot: snapshot, projection: projection, translation: .init(x: 10, y: 10))
            if resetFirst { lifecycle.gestureBecameInactive() }
            XCTAssertNotNil(lifecycle.finish())
            if !resetFirst { lifecycle.gestureBecameInactive() }
            XCTAssertNil(lifecycle.preview)
        }
        var cancelled = NodeDragLifecycle()
        try cancelled.update(
            anchorID: "a", snapshot: snapshot, projection: projection, translation: .init(x: 10, y: 10))
        cancelled.gestureBecameInactive()
        XCTAssertNil(cancelled.preview)
        try cancelled.update(
            anchorID: "b", snapshot: snapshot, projection: projection, translation: .init(x: 20, y: 20))
        XCTAssertEqual(cancelled.finish()?.anchorID, "b")
    }

    func testInvalidationDoesNotRestartUntilGestureEnds() async throws {
        let session = EditorSession()
        let snapshot = try await session.open(data: data())
        let projection = CanvasProjection(bounds: .init(nodes: snapshot.nodes), plane: .front, width: 472, height: 472)
        var lifecycle = NodeDragLifecycle()
        try lifecycle.update(
            anchorID: "a", snapshot: snapshot, projection: projection, translation: .init(x: 10, y: 10))
        lifecycle.invalidate()
        try lifecycle.update(
            anchorID: "a", snapshot: snapshot, projection: projection, translation: .init(x: 20, y: 20))
        XCTAssertNil(lifecycle.finish())
        lifecycle.gestureBecameInactive()
        try lifecycle.update(
            anchorID: "a", snapshot: snapshot, projection: projection, translation: .init(x: 10, y: 10))
        XCTAssertNotNil(lifecycle.finish())
    }
}
