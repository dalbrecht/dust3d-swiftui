import Dust3DDocument
import Dust3DKit
import XCTest
import simd

@testable import Dust3DEditor

final class ComponentWrappingStoreTests: XCTestCase {
    private let groupID = WrappingFixture.groupID
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<3000 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Wrapping edit or generation did not settle within 30 seconds")
    }
    private func assertFinite(_ mesh: Mesh) {
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        for vertex in mesh.vertices {
            for axis in 0..<3 { XCTAssertTrue(vertex.position[axis].isFinite) }
            XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.0001)
        }
    }
    @MainActor func testControllerEditsRegeneratePreserveSelectionCameraAssetsAndExactHistory() async throws {
        let source = try WrappingFixture.document()
        let store = EditorStore()
        defer { store.stop() }
        var saved: Data?
        store.onDocumentChanged = { saved = $0 }
        await store.load(data: source.encoded())
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        store.selectComponent(groupID)
        try await settle(store)
        let camera = store.cameraReset
        store.setComponentWrapMode(groupID, mode: .cloth)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.previewState.errorMessage)
        assertFinite(try XCTUnwrap(store.mesh))
        XCTAssertNotEqual(store.mesh?.triangleCount, baseline.triangleCount)
        XCTAssertEqual(store.snapshot?.selectedComponent?.wrapping.mode, .cloth)
        store.setComponentWrapKeepChildren(groupID, value: false)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.wrapping.keepsChildren, false)
        store.setComponentWrapFaces(groupID, faces: "128")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.wrapping.targetFaces, 128)
        let beforeScalar = try XCTUnwrap(store.snapshot?.document.encoded())
        store.setComponentWrapScalar(groupID, property: .offset, value: "0,05")
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(saved, changed)
        XCTAssertEqual(try Dust3DDocument(data: changed).asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
        XCTAssertEqual(try Dust3DDocument(data: changed).editorContents().nodes, try source.editorContents().nodes)
        XCTAssertEqual(store.snapshot?.selectedComponentID, groupID)
        XCTAssertEqual(store.cameraReset, camera)
        let count = try XCTUnwrap(store.mesh).triangleCount
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), beforeScalar)
        let revision = store.previewRevision
        store.setComponentWrapScalar(groupID, property: .offset, value: "0.012")
        try await settle(store)
        XCTAssertTrue(store.canRedo)
        XCTAssertEqual(store.previewRevision, revision)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        XCTAssertEqual(store.mesh?.triangleCount, count)
    }
    @MainActor func testInvalidDraftsAndOwnersPreserveBytesRedoAndPublicationCount() async throws {
        let source = try WrappingFixture.document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.setComponentWrapMode(groupID, mode: .cloth)
        try await settle(store)
        store.undo()
        try await settle(store)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        let revision = store.previewRevision
        for property in ComponentWrappingScalarProperty.allCases {
            for text in ["", "future", "nan", "inf", "-0.1", String(property.bounds.upperBound + 1), "1e-50", "1e-999"]
            {
                store.setComponentWrapScalar(groupID, property: property, value: text)
                try await settle(store)
                XCTAssertNotNil(store.errorMessage)
            }
        }
        for text in ["", "future", "64.0", "63", "20001", "1e2", String(Int.max)] {
            store.setComponentWrapFaces(groupID, faces: text)
            try await settle(store)
            XCTAssertNotNil(store.errorMessage)
        }
        store.setComponentWrapMode("missing", mode: .cloth)
        try await settle(store)
        XCTAssertTrue(store.errorMessage?.contains("not present") == true)
        store.setComponentWrapKeepChildren(StitchingFixture.identity(200), value: true)
        try await settle(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertTrue(store.canRedo)
        store.stop()
        store.errorMessage = nil
        store.setComponentWrapScalar(groupID, property: .offset, value: "invalid")
        store.setComponentWrapFaces(groupID, faces: "invalid")
        store.setComponentWrapMode(groupID, mode: .skin)
        store.setComponentWrapKeepChildren(groupID, value: true)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(publications, 0)
    }
    @MainActor func testEveryScalarDraftIncludingRepairedOpeningsProducesFinitePreview() async throws {
        let source = try WrappingFixture.document(mode: "Cloth")
        for property in ComponentWrappingScalarProperty.allCases {
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: source.encoded())
            try await settle(store)
            store.setComponentWrapScalar(groupID, property: property, value: String(property.bounds.upperBound / 2))
            try await settle(store)
            XCTAssertNil(store.errorMessage)
            XCTAssertNil(store.previewState.errorMessage)
            XCTAssertFalse(store.previewState.isStale)
            assertFinite(try XCTUnwrap(store.mesh))
        }
    }
}
