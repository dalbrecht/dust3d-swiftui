import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class EmptyPartStoreTests: XCTestCase {
    @MainActor
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Deletion did not settle")
    }

    @MainActor
    func testDeletingFinalNodeClearsPartAndPreviewWithExactUndoAndRedo() async throws {
        let nodeID = "{11111111-1111-4111-8111-111111111111}"
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: nodeID, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0.5, y: 0.5, z: 1),
                radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        store.select(nodeID)
        try await settle(store)
        store.deleteSelection()
        try await settle(store)
        XCTAssertTrue(try XCTUnwrap(store.snapshot?.parts.isEmpty))
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.canUndo)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        XCTAssertFalse(store.canUndo)
        store.redo()
        try await settle(store)
        XCTAssertTrue(try XCTUnwrap(store.snapshot?.parts.isEmpty))
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
    }
}
