import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class PartTargetStoreTests: XCTestCase {
    private let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Target-role operation or generation did not settle")
    }

    @MainActor func testProfileRoleClearsPreviewKeepsEditableSourceAndRestoresExactHistory() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: part,
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        store.selectPart(part)
        try await settle(store)
        let camera = store.cameraReset
        let nodes = store.snapshot?.nodes
        store.setPartTarget(part, target: .cutFace)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertFalse(store.isGenerating)
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertEqual(store.snapshot?.nodes, nodes)
        XCTAssertEqual(store.snapshot?.selectedPartID, part)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(publications, 1)
        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(try Dust3DDocument(data: changed).editorContents().parts.first?.target, .cutFace)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.mesh?.vertices.map(\.position), baseline.vertices.map(\.position))
        let revision = store.previewRevision
        store.setPartTarget(part, target: .model)
        try await settle(store)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertTrue(store.canRedo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        XCTAssertNil(store.mesh)
        store.setPartTarget(part, target: .model)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.parts.first?.target, .model)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), baseline.vertices.map(\.position))
    }
}
