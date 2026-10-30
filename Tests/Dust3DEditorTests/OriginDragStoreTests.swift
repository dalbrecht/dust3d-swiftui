import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class OriginDragStoreTests: XCTestCase {
    func testEscapePrioritizesOriginModeOverConcurrentExport() {
        var originCancellations = 0
        var exportCancellations = 0
        EditorCommandScope.routeEscape(
            isMovingOrigin: true, canCancelExport: true,
            cancelOrigin: { originCancellations += 1 }, cancelExport: { exportCancellations += 1 })
        XCTAssertEqual(originCancellations, 1)
        XCTAssertEqual(exportCancellations, 0)
        EditorCommandScope.routeEscape(
            isMovingOrigin: false, canCancelExport: true,
            cancelOrigin: { originCancellations += 1 }, cancelExport: { exportCancellations += 1 })
        XCTAssertEqual(exportCancellations, 1)
        EditorCommandScope.routeEscape(
            isMovingOrigin: false, canCancelExport: false,
            cancelOrigin: { originCancellations += 1 }, cancelExport: { exportCancellations += 1 })
        XCTAssertEqual(originCancellations, 1)
        XCTAssertEqual(exportCancellations, 1)
    }
    @MainActor
    func testLateCallbacksCannotChangeNewOriginGesture() async throws {
        let original = Dust3DDocument.emptyArchive()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original)
        try await settle(store)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        let first = UUID()
        let second = UUID()
        store.setMovingOrigin(true)
        store.beginOriginDrag(token: first, projection: projection)
        store.updateOriginDrag(token: first, translation: .init(x: 10, y: 20))
        store.cancelOriginDrag()
        store.setMovingOrigin(true)
        store.beginOriginDrag(token: second, projection: projection)
        store.updateOriginDrag(token: second, translation: .init(x: 30, y: 40))
        let preview = store.originDragPosition
        store.updateOriginDrag(token: first, translation: .init(x: 80, y: 90))
        store.finishOriginDrag(token: first, translation: .init(x: 80, y: 90))
        store.cancelOriginDrag(token: first)
        XCTAssertEqual(store.originDragPosition, preview)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
        store.finishOriginDrag(token: second, translation: .init(x: 30, y: 40))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, preview)
        XCTAssertTrue(store.canUndo)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }

    @MainActor
    func testOriginClickEndsOnlyItsOwnDraftAndKeepsMode() async throws {
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: Dust3DDocument.emptyArchive())
        try await settle(store)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        let old = UUID()
        let active = UUID()
        store.setMovingOrigin(true)
        store.beginOriginDrag(token: old, projection: projection)
        store.endOriginClick(token: old)
        XCTAssertTrue(store.isMovingOrigin)
        store.beginOriginDrag(token: active, projection: projection)
        store.updateOriginDrag(token: active, translation: .init(x: 20, y: 10))
        let preview = store.originDragPosition
        store.endOriginClick(token: old)
        XCTAssertEqual(store.originDragPosition, preview)
        XCTAssertFalse(store.canUndo)
    }

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
        let token = UUID()
        let camera = store.cameraReset
        var writes = 0
        store.onDocumentChanged = { _ in writes += 1 }
        store.setMovingOrigin(true)
        store.beginOriginDrag(token: token, projection: projection)
        store.updateOriginDrag(token: token, translation: .init(x: 40, y: 80))
        XCTAssertNotNil(store.originDragPosition)
        store.updateOriginDrag(token: token, translation: .init(x: 40, y: 80))
        XCTAssertEqual(store.originDragPosition, projection.moving(origin, by: .init(x: 40, y: 80)))
        XCTAssertEqual(store.snapshot?.origin, origin)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(other.isMovingOrigin)
        XCTAssertNil(other.originDragPosition)
        store.cancelOriginDrag()
        store.finishOriginDrag(token: token, translation: .init(x: 40, y: 80))
        XCTAssertEqual(store.snapshot?.document.encoded(), data)
        XCTAssertEqual(writes, 0)
        store.setMovingOrigin(true)
        store.beginOriginDrag(token: token, projection: projection)
        store.updateOriginDrag(token: token, translation: .init(x: 40, y: 80))
        let preview = store.originDragPosition
        store.finishOriginDrag(token: token, translation: .init(x: 40, y: 80))
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
        store.beginOriginDrag(token: token, projection: projection)
        store.updateOriginDrag(token: token, translation: .init(x: 10, y: 10))
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
        let token = UUID()
        func begin() {
            store.setMovingOrigin(true)
            store.beginOriginDrag(token: token, projection: projection)
            store.updateOriginDrag(token: token, translation: .init(x: 40, y: 80))
            XCTAssertNotNil(store.originDragPosition)
        }
        begin()
        store.setLock(.radius, isLocked: true)
        try await settle(store)
        XCTAssertNil(store.originDragPosition)
        store.finishOriginDrag(token: token, translation: .init(x: 40, y: 80))
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
        store.finishOriginDrag(token: token, translation: .init(x: 40, y: 80))
        XCTAssertEqual(store.snapshot?.document.encoded(), data)
    }
}
