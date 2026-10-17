import Dust3DDocument
import XCTest

@testable import Dust3DEditor

@MainActor
final class PartMaterialStoreTests: XCTestCase {
    func testAppliedMaterialDraftsPreserveSelectionCameraHistoryAndPreviewGeometry() async throws {
        let source = try StitchingFixture.document(loop: true, isolatedLoop: true)
        let part = StitchingFixture.identity(199)
        for property in PartMaterialProperty.allCases {
            let store = EditorStore()
            defer { store.stop() }
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            await store.load(data: source.encoded())
            try await settle(store)
            store.selectPart(part)
            try await settle(store)
            let mesh = try XCTUnwrap(store.mesh)
            let camera = store.cameraReset
            store.setPartMaterial(part, property: property, value: property == .emissive ? "2" : "0,5")
            try await settle(store)
            XCTAssertNil(store.errorMessage)
            XCTAssertEqual(
                store.snapshot?.parts.first(where: { $0.id == part })?.materialValue(property),
                property == .emissive ? 2 : 0.5)
            XCTAssertEqual(store.snapshot?.selectedPartID, part)
            XCTAssertEqual(store.cameraReset, camera)
            XCTAssertEqual(store.mesh?.vertices.map(\.position), mesh.vertices.map(\.position))
            XCTAssertEqual(publications, 1)
            let changed = try XCTUnwrap(store.snapshot?.document.encoded())
            let revision = store.previewRevision
            store.setPartMaterial(part, property: property, value: property == .emissive ? "2" : "0.5")
            try await settle(store)
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(store.previewRevision, revision)
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), changed)
            XCTAssertEqual(try Dust3DDocument(data: changed).editorContents().parts, store.snapshot?.parts)
        }
    }

    func testInvalidMaterialDraftsDoNotPublishAndStoppedStoreIgnoresEdits() async throws {
        let source = try StitchingFixture.document(loop: true, isolatedLoop: true)
        let store = EditorStore()
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: source.encoded())
        try await settle(store)
        let revision = store.previewRevision
        for property in PartMaterialProperty.allCases {
            for text in ["", "future", "nan", "inf", "-0.01", "2.01", "1e-50", "1e-999"] {
                store.setPartMaterial(StitchingFixture.identity(199), property: property, value: text)
                try await settle(store)
                XCTAssertNotNil(store.errorMessage)
                XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
                XCTAssertEqual(store.previewRevision, revision)
                XCTAssertEqual(publications, 0)
            }
        }
        store.stop()
        store.setPartMaterial(StitchingFixture.identity(199), property: .metallic, value: "0.5")
        XCTAssertEqual(publications, 0)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Material operation did not settle")
    }
}
