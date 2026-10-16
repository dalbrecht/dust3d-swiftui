import Dust3DDocument
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class OriginSettlementStoreTests: XCTestCase {
    @MainActor
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Origin settlement did not settle")
    }

    @MainActor
    func testCenterCommandPreservesNodesLocksCameraAndLosslessUndo() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 2, y: -3, z: 4), radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let camera = store.cameraReset
        let node = try XCTUnwrap(store.snapshot?.nodes.first)
        store.setLock(.x, isLocked: true)
        try await settle(store)
        let oldX = store.snapshot?.origin?.x
        store.setMovingOrigin(true)
        store.centerOriginOnModel()
        try await settle(store)
        XCTAssertFalse(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.origin?.x, oldX)
        XCTAssertEqual(store.snapshot?.origin?.y, -3)
        XCTAssertEqual(store.snapshot?.origin?.z, 4)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.snapshot?.nodes.first, node)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        let saved = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(try Dust3DDocument(data: saved).origin(), store.snapshot?.origin)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
    }
}
