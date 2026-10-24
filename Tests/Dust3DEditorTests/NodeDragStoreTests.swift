import Dust3DDocument
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class NodeDragStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Node drag did not settle")
    }

    @MainActor func testCancelRejectsLateCallbacksAndFreshGestureHasExactUndo() async throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "a", partID: "p", componentID: "c",
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 400)
        let old = store.canvasDragGeneration
        store.updateNodeDrag(anchorID: "a", translation: .init(x: 20, y: 10), projection: projection, generation: old)
        XCTAssertTrue(store.hasNodeDrag)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        store.cancelCanvasDrag()
        XCTAssertFalse(store.hasNodeDrag)
        store.updateNodeDrag(anchorID: "a", translation: .init(x: 40, y: 10), projection: projection, generation: old)
        store.finishNodeDrag(translation: .init(x: 40, y: 10), generation: old)
        try await settle(store)
        XCTAssertFalse(store.hasNodeDrag)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        let fresh = store.canvasDragGeneration
        store.updateNodeDrag(anchorID: "a", translation: .init(x: 20, y: 10), projection: projection, generation: fresh)
        store.finishNodeDrag(translation: .init(x: 20, y: 10), generation: fresh)
        try await settle(store)
        let saved = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertNotEqual(saved, source.encoded())
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
    }
}
