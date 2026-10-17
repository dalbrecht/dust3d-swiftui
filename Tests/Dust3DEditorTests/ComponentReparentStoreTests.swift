import Dust3DDocument
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class ComponentReparentStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component ordering or generation did not settle")
    }
    @MainActor func testReparentPublishesOnceRejectsStaleTargetsAndRestoresExactHistory() async throws {
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
        let destination = "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}"
        original = try original.applying(.groupComponents(ids: [last], groupID: destination))
        let store = EditorStore()
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectComponent(first)
        try await settle(store)
        let target = try XCTUnwrap(store.snapshot.flatMap(ComponentReparentTarget.init(snapshot:)))
        store.selectComponent(last)
        try await settle(store)
        store.reparentComponent(to: .component(destination), target: target)
        try await settle(store)
        XCTAssertEqual(store.errorMessage, "The document or component selection changed. Reset the parent chooser.")
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(publications, 0)
        store.selectComponent(first)
        try await settle(store)
        let fresh = try XCTUnwrap(store.snapshot.flatMap(ComponentReparentTarget.init(snapshot:)))
        let camera = store.cameraReset
        let preview = store.previewRevision
        var didComplete = false
        store.reparentComponent(to: .component(destination), target: fresh) { didComplete = $0 }
        try await settle(store)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(store.snapshot?.selectedComponent?.parentID, destination)
        XCTAssertEqual(store.snapshot?.selectedComponentID, first)
        XCTAssertEqual(publications, 1)
        XCTAssertGreaterThan(store.previewRevision, preview)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        let changed = store.snapshot?.document.encoded()
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        store.stop()
        store.reparentComponent(to: .root, target: fresh) { didComplete = $0 }
        XCTAssertFalse(didComplete)
    }
}
