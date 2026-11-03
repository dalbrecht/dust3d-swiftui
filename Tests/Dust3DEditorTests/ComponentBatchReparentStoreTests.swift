import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct ReparentNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    { throw CancellationError() }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}
@MainActor final class ComponentBatchReparentStoreTests: XCTestCase {
    func testChooserActionRejectsSelectionABAAndMovesOnceWithUndo() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><components><component id='a'/><component id='b'/><component id='destination' name='Destination'><component id='stay'/></component></components></canvas>"
                    .utf8
            ))
        let stub = ReparentNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: document.encoded())
        try await settle(store)
        store.selectComponents(["a", "b"])
        try await settle(store)
        let target = try XCTUnwrap(store.snapshot.flatMap(ComponentBatchReparentTarget.init(snapshot:)))
        XCTAssertEqual(target.parentOptions(matching: "destination").map(\.id), [.component("destination")])
        XCTAssertEqual(target.parentOptions().map(\.id), [.component("destination"), .component("stay")])
        let action = { store.reparentComponents(to: .component("destination"), target: target) }
        store.selectComponent("a")
        try await settle(store)
        store.selectComponents(["a", "b"])
        try await settle(store)
        action()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertEqual(publications, 0)

        let current = try XCTUnwrap(store.snapshot.flatMap(ComponentBatchReparentTarget.init(snapshot:)))
        var completed = false
        store.reparentComponents(to: .component("destination"), target: current) {
            completed = $0
        }
        try await settle(store)
        XCTAssertTrue(completed)
        XCTAssertEqual(store.snapshot?.componentTree.rows.first?.component.childIDs, ["stay", "a", "b"])
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(publications, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Batch reparent Store did not settle")
    }
}
