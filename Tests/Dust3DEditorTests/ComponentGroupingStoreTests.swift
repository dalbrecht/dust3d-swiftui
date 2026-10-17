import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class ComponentGroupingStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component ordering or generation did not settle")
    }
    @MainActor func testMultiSelectionGroupingAndUngroupingRegenerateWithExactUndoAndRedo() async throws {
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
        XCTAssertFalse(store.canGroupComponents)
        store.groupSelectedComponents()
        store.ungroupSelectedComponent()
        store.selectComponents([first, last])
        try await settle(store)
        XCTAssertTrue(store.canGroupComponents)
        XCTAssertFalse(store.canUngroupComponent)
        XCTAssertNil(store.snapshot?.selectedComponentID)
        XCTAssertFalse(store.snapshot?.canAddNode == true)
        XCTAssertEqual(publications, 0)
        let camera = store.cameraReset
        let preview = store.previewRevision
        store.groupSelectedComponents()
        try await settle(store)
        let group = try XCTUnwrap(store.snapshot?.selectedComponentID)
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, [group])
        XCTAssertEqual(store.snapshot?.selectedComponent?.childIDs, [first, last])
        XCTAssertTrue(store.canUngroupComponent)
        XCTAssertEqual(publications, 1)
        XCTAssertGreaterThan(store.previewRevision, preview)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        let grouped = store.snapshot?.document.encoded()
        store.ungroupSelectedComponent()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), [first, last])
        XCTAssertTrue(store.snapshot?.selectedComponentIDs.isEmpty == true)
        XCTAssertEqual(publications, 2)
        let ungrouped = store.snapshot?.document.encoded()
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), grouped)
        XCTAssertTrue(store.snapshot?.selectedComponentIDs.isEmpty == true)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settle(store)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), ungrouped)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        store.stop()
        XCTAssertFalse(store.canGroupComponents)
        XCTAssertFalse(store.canUngroupComponent)
    }
}
