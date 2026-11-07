import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct LockedTransformNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class LockedTransformStoreTests: XCTestCase {
    func testStoreMasksLockedDraftValuesBeforeDispatch() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='2' y='4' z='6' radius='.2'/>
                </nodes><parts><part id='p'/></parts></canvas>
                """.utf8))
        let stub = LockedTransformNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }

        await store.load(data: source.encoded())
        try await settle(store)
        store.select(Set(["a", "b"]))
        try await settle(store)
        store.setLock(.radius, isLocked: true)
        try await settle(store)
        XCTAssertEqual(store.locks, [.radius])

        store.scaleSelection(positionFactor: 2, radiusFactor: 0)
        try await settle(store)
        let scaled = try XCTUnwrap(store.snapshot).document
        XCTAssertEqual(try scaled.node(id: "a").position, .init(x: -1, y: -2, z: -3))
        XCTAssertEqual(try scaled.node(id: "b").position, .init(x: 3, y: 6, z: 9))
        XCTAssertEqual(try scaled.node(id: "a").radius, 0.1)
        XCTAssertEqual(try scaled.node(id: "b").radius, 0.2)
        XCTAssertNil(store.errorMessage)

        store.setLock(.x, isLocked: true)
        try await settle(store)
        store.moveSelection(by: .init(x: .nan, y: 1, z: 0))
        try await settle(store)
        let moved = try XCTUnwrap(store.snapshot).document
        XCTAssertEqual(try moved.node(id: "a").position, .init(x: -1, y: -1, z: -3))
        XCTAssertEqual(try moved.node(id: "b").position, .init(x: 3, y: 7, z: 9))
        XCTAssertNil(store.errorMessage)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Transform did not settle")
    }
}
