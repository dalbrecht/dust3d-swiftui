import Dust3DDocument
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class DescendantRotationStoreTests: XCTestCase {
    @MainActor
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Descendant rotation did not settle")
    }

    @MainActor
    func testAvailabilityRotationCameraUndoAndInvalidSelectionPreserveState() async throws {
        let ids = [
            "{11111111-1111-4111-8111-111111111111}", "{22222222-2222-4222-8222-222222222222}",
            "{33333333-3333-4333-8333-333333333333}",
        ]
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        var original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ids.enumerated() {
            original = try original.applying(
                .addNode(
                    id: id, partID: part, componentID: index == 0 ? "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}" : nil,
                    position: .init(x: 0.5, y: 0.25 + Double(index) * 0.25, z: 1), radius: 0.1))
        }
        original = try original.applying(
            .addEdge(id: "{44444444-4444-4444-8444-444444444444}", from: ids[0], to: ids[1]))
        original = try original.applying(
            .addEdge(id: "{55555555-5555-4555-8555-555555555555}", from: ids[1], to: ids[2]))
        let store = EditorStore()
        defer { store.stop() }
        XCTAssertFalse(store.canRotateDescendants)
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertFalse(store.canRotateDescendants)
        store.select(ids[1])
        try await settle(store)
        XCTAssertTrue(store.canRotateDescendants)
        let camera = store.cameraReset
        store.rotateDescendants(.frontClockwise)
        try await settle(store)
        XCTAssertEqual(try store.snapshot?.document.node(id: ids[2]).position, .init(x: 0.25, y: 0.5, z: 1))
        XCTAssertEqual(try store.snapshot?.document.node(id: ids[1]), try original.node(id: ids[1]))
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertGreaterThan(try XCTUnwrap(store.mesh?.triangleCount), 0)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        store.selectAll()
        try await settle(store)
        XCTAssertFalse(store.canRotateDescendants)
        store.rotateDescendants(.frontClockwise)
        try await settle(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.canRedo)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
    }
}
