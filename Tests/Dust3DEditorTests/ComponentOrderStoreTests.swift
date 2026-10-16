import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class ComponentOrderStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component ordering or generation did not settle")
    }
    @MainActor func testReorderRegeneratesPreviewPublishesOneEditAndKeepsSelectionAndCamera() async throws {
        let first = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
        let last = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        var original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (node, part, component, x) in [
            ("{11111111-1111-4111-8111-111111111111}", "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", first, 0.5),
            ("{22222222-2222-4222-8222-222222222222}", "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", last, 3.0),
        ] {
            original = try original.applying(
                .addNode(
                    id: node, partID: part, componentID: component, position: .init(x: x, y: 0.5, z: 0.5), radius: 0.1))
        }
        let store = EditorStore()
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertFalse(store.canReorderComponent(.up))
        store.reorderComponent(.up)
        store.selectComponent(last)
        try await settle(store)
        XCTAssertTrue(store.canReorderComponent(.up))
        XCTAssertFalse(store.canReorderComponent(.down))
        let camera = store.cameraReset
        let preview = store.previewRevision
        store.reorderComponent(.first)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), [last, first])
        XCTAssertEqual(store.snapshot?.selectedComponentID, last)
        XCTAssertEqual(publications, 1)
        XCTAssertGreaterThan(store.previewRevision, preview)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        let edited = store.snapshot?.document.encoded()
        let completedPreview = store.previewRevision
        store.reorderComponent(.up)
        try await settle(store)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.previewRevision, completedPreview)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), edited)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        store.stop()
        XCTAssertFalse(store.canReorderComponent(.down))
    }
}
