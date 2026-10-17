import Dust3DDocument
import XCTest
import simd

@testable import Dust3DEditor

final class ComponentSmoothingStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component smoothing did not settle")
    }

    @MainActor func testCutoffChangesRealNormalsWithoutChangingGeometryCameraOrSelectionAndUndoRestoresArchive()
        async throws
    {
        let component = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: component, position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectComponent(component)
        try await settle(store)
        let flat = try XCTUnwrap(store.mesh)
        let camera = store.cameraReset
        store.setComponentSmoothCutoff(component, degrees: "180")
        try await settle(store)
        let smooth = try XCTUnwrap(store.mesh)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.selectedComponentID, component)
        XCTAssertEqual(store.snapshot?.selectedComponent?.smoothCutoffDegrees, 180)
        // Smoothing merges attribute-identical vertices; compare reconstructed triangle corners.
        XCTAssertEqual(
            flat.indices.map { flat.vertices[Int($0)].position },
            smooth.indices.map { smooth.vertices[Int($0)].position })
        XCTAssertLessThan(smooth.vertices.count, flat.vertices.count)
        XCTAssertNotEqual(flat.vertices.map(\.normal), smooth.vertices.map(\.normal))
        XCTAssertTrue(smooth.vertices.allSatisfy { abs(simd_length($0.normal) - 1) < 0.0001 })
        XCTAssertEqual(smooth.triangleCount, 16)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(publications, 1)
        let changed = store.snapshot?.document.encoded()
        let preview = store.previewRevision
        store.setComponentSmoothCutoff(component, degrees: "180.00")
        try await settle(store)
        XCTAssertEqual(store.previewRevision, preview)
        XCTAssertEqual(publications, 1)
        for invalid in ["", "nan", "inf", "-1", "181", "future"] {
            store.setComponentSmoothCutoff(component, degrees: invalid)
            try await settle(store)
            XCTAssertEqual(store.errorMessage, "Enter a finite smoothing cutoff from 0 to 180 degrees.")
            XCTAssertEqual(store.snapshot?.document.encoded(), changed)
            XCTAssertEqual(publications, 1)
        }
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.mesh?.vertices.map(\.normal), flat.vertices.map(\.normal))
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        XCTAssertEqual(store.mesh?.vertices.map(\.normal), smooth.vertices.map(\.normal))
        store.setComponentSmoothCutoff(component, degrees: "0")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.smoothCutoffDegrees, 0)
        XCTAssertEqual(store.mesh?.vertices.map(\.normal), flat.vertices.map(\.normal))
        store.stop()
        store.setComponentSmoothCutoff(component, degrees: "90")
        XCTAssertEqual(store.snapshot?.selectedComponent?.smoothCutoffDegrees, 0)
    }
}
