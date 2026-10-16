import Dust3DDocument
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class OriginDragStoreTests: XCTestCase {
    @MainActor
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Origin drag did not settle")
    }

    @MainActor
    func testTransientPreviewCancelCommitUndoAndWindowIsolation() async throws {
        let data = Dust3DDocument.emptyArchive()
        let store = EditorStore()
        let other = EditorStore()
        defer {
            store.stop()
            other.stop()
        }
        await store.load(data: data)
        await other.load(data: data)
        try await settle(store)
        try await settle(other)
        let origin = try XCTUnwrap(store.snapshot?.origin)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        let camera = store.cameraReset
        var writes = 0
        store.onDocumentChanged = { _ in writes += 1 }
        store.setMovingOrigin(true)
        store.updateOriginDrag(translation: .init(x: 40, y: 80), projection: projection)
        XCTAssertNotNil(store.originDragPosition)
        let resized = CanvasProjection(bounds: store.bounds, plane: .side, width: 872, height: 872)
        store.updateOriginDrag(translation: .init(x: 40, y: 80), projection: resized)
        XCTAssertEqual(store.originDragPosition, projection.moving(origin, by: .init(x: 40, y: 80)))
        XCTAssertEqual(store.snapshot?.origin, origin)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(other.isMovingOrigin)
        XCTAssertNil(other.originDragPosition)
        store.cancelOriginDrag()
        store.finishOriginDrag(translation: .init(x: 40, y: 80))
        XCTAssertEqual(store.snapshot?.document.encoded(), data)
        XCTAssertEqual(writes, 0)
        store.setMovingOrigin(true)
        store.updateOriginDrag(translation: .init(x: 40, y: 80), projection: projection)
        let preview = store.originDragPosition
        store.finishOriginDrag(translation: .init(x: 40, y: 80))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, preview)
        XCTAssertNil(store.originDragPosition)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(writes, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), data)
        XCTAssertFalse(store.canUndo)
        store.setMovingOrigin(true)
        store.updateOriginDrag(translation: .init(x: 10, y: 10), projection: projection)
        store.cancelOriginDrag()
        XCTAssertTrue(store.canRedo)
        XCTAssertEqual(store.snapshot?.document.encoded(), data)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, preview)
    }

    @MainActor
    func testLockPlaneLoadAndStopCancelGestureWithoutSaving() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let data = Dust3DDocument.emptyArchive()
        await store.load(data: data)
        try await settle(store)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        func begin() {
            store.setMovingOrigin(true)
            store.updateOriginDrag(translation: .init(x: 40, y: 80), projection: projection)
            XCTAssertNotNil(store.originDragPosition)
        }
        begin()
        store.setLock(.radius, isLocked: true)
        try await settle(store)
        XCTAssertNil(store.originDragPosition)
        store.finishOriginDrag(translation: .init(x: 40, y: 80))
        XCTAssertFalse(store.canUndo)
        begin()
        store.plane = .side
        XCTAssertNil(store.originDragPosition)
        begin()
        await store.load(data: data)
        XCTAssertFalse(store.isMovingOrigin)
        XCTAssertNil(store.originDragPosition)
        try await settle(store)
        begin()
        store.stop()
        XCTAssertNil(store.originDragPosition)
        store.finishOriginDrag(translation: .init(x: 40, y: 80))
        XCTAssertEqual(store.snapshot?.document.encoded(), data)
    }
}
