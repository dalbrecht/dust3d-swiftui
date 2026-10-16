import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class ComponentStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component operation did not settle")
    }
    @MainActor func testComponentSelectionRenameErrorsUndoAndRedoRetainGeometryAndPublishOnlyEdits() async throws {
        let componentID = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: componentID, position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
        let store = EditorStore()
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let camera = store.cameraReset
        store.selectComponent(componentID)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.id, componentID)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(store.canAddNode)
        store.renameComponent(componentID, name: "Assembly")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.name, "Assembly")
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        XCTAssertEqual(store.cameraReset, camera)
        let saved = store.snapshot?.document.encoded()
        store.renameComponent(componentID, name: "bad\u{007F}name")
        try await settle(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.snapshot?.selectedComponentID, componentID)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        store.selectPart("{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}")
        try await settle(store)
        XCTAssertNil(store.snapshot?.selectedComponentID)
    }
}
