import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class ComponentCombineStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component combination or generation did not settle")
    }

    @MainActor func testCombinationRegeneratesOneEditKeepsCameraAndSelectionAndRestoresExactHistory() async throws {
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
        store.selectComponent(last)
        try await settle(store)
        let camera = store.cameraReset
        let preview = store.previewRevision
        store.setComponentCombineMode(last, mode: .inversion)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.selectedComponentID, last)
        XCTAssertEqual(store.snapshot?.selectedComponent?.combineMode, .inversion)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertGreaterThan(store.previewRevision, preview)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        XCTAssertTrue(store.mesh?.vertices.allSatisfy { $0.position.x < 1 } == true)
        let edited = store.snapshot?.document.encoded()
        store.setComponentCombineMode(last, mode: .inversion)
        try await settle(store)
        XCTAssertEqual(publications, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), edited)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        store.setComponentCombineMode(last, mode: .uncombined)
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        XCTAssertEqual(store.cameraReset, camera)
    }
}
