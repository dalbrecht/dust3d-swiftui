import Dust3DDocument
import XCTest

@testable import Dust3DEditor

@MainActor
final class ComponentColorStoreTests: XCTestCase {
    private let component = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}",
                partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", componentID: component,
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
    }

    func testColorApplyUpdatesActualMeshAndPreservesSelectionCameraAndExactHistory() async throws {
        let source = try document()
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectComponent(component)
        try await settle(store)
        let mesh = try XCTUnwrap(store.mesh)
        let camera = store.cameraReset
        let revision = store.previewRevision
        store.setComponentColor(component, value: "#8000ff00")
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        let colored = try XCTUnwrap(store.mesh)
        XCTAssertGreaterThan(store.previewRevision, revision)
        XCTAssertEqual(colored.triangleCount, mesh.triangleCount)
        XCTAssertTrue(
            colored.vertices.allSatisfy { $0.color.x == 0 && $0.color.y == 1 && $0.color.z == 0 && $0.color.w == 1 })
        XCTAssertEqual(store.snapshot?.selectedComponentID, component)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(publications, 1)
        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        let changedRevision = store.previewRevision
        store.setComponentColor(component, value: "#8000FF00")
        try await settle(store)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.previewRevision, changedRevision)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.mesh?.vertices.map(\.color), mesh.vertices.map(\.color))
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        XCTAssertEqual(store.mesh?.vertices.map(\.color), colored.vertices.map(\.color))
        store.removeComponentColor(component)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.color, .unset)
        XCTAssertEqual(store.mesh?.vertices.map(\.color), mesh.vertices.map(\.color))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
    }

    func testInvalidColorDraftsAndStoppedEditsDoNotPublishOrRegenerate() async throws {
        let source = try document()
        let store = EditorStore()
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: source.encoded())
        try await settle(store)
        let revision = store.previewRevision
        for text in ["", "red", "#123", "#001122GG", " #123456", "#123456\n"] {
            store.setComponentColor(component, value: text)
            try await settle(store)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(store.previewRevision, revision)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        }
        store.stop()
        store.setComponentColor(component, value: "#123456")
        store.removeComponentColor(component)
        XCTAssertEqual(publications, 0)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Color operation did not settle")
    }
}
