import Dust3DDocument
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

@MainActor
final class EditorSourceBakedMaterialTests: XCTestCase {
    func testConfirmedSourceFrameClearsLegacyDetailNotice() async throws {
        let original = try Dust3DDocument(data: source())
        let xml = try XCTUnwrap(String(data: original.modelXML, encoding: .utf8))
            .replacingOccurrences(of: "<component ", with: "<component wrapWrinkles='0' ")
        var payload = Data(xml.utf8)
        var header = "<ds3><model name='model.xml' offset='0' size='\(payload.count)'/>"
        for name in [
            "models/{00000300-0000-4000-8000-000000000300}.glb",
            "images/{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}.png", "opaque.bin",
        ] {
            let bytes = try XCTUnwrap(original.asset(named: name))
            header += "<asset name='\(name)' offset='\(payload.count)' size='\(bytes.count)'/>"
            payload.append(bytes)
        }
        header += "</ds3>"
        let bytes = Data("DUST3D 1.0 xml \(String(format: "%010d", 26 + header.utf8.count))\n\(header)".utf8) + payload
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: bytes)
        await settle(store)
        XCTAssertNotNil(store.sourceBakedMesh)
        XCTAssertTrue(store.previewCompatibilityWarning?.contains("surface details") == true)
        let revision = store.materialViewportRevision
        store.materialsRendered(revision: revision - 1)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        store.materialsRendered(revision: revision)
        XCTAssertNil(store.previewCompatibilityWarning)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
    }

    func testPresentsBothMixedSurfaceKindsOnlyForTheCurrentGpuFrame() async throws {
        let bytes = try source()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: bytes)
        await settle(store)
        let materials = try XCTUnwrap(store.sourceBakedMesh)
        XCTAssertTrue(materials.triangles.contains { $0.modelIndex == 0 && $0.packedUVs != nil })
        XCTAssertTrue(materials.triangles.contains { $0.modelIndex == nil && $0.packedUVs != nil })
        XCTAssertNil(store.importedMaterials)
        XCTAssertNil(store.bakedMesh)
        XCTAssertNil(store.materialIssue)
        XCTAssertTrue(store.isUpdatingMaterials)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        let revision = store.materialViewportRevision
        store.materialsRendered(revision: revision - 1)
        XCTAssertTrue(store.isUpdatingMaterials)
        store.materialsRendered(revision: revision)
        XCTAssertFalse(store.isUpdatingMaterials)
        XCTAssertNil(store.previewCompatibilityWarning)
        store.materialsFailed("stale mixed GPU cause", revision: revision - 1)
        XCTAssertNotNil(store.sourceBakedMesh)
        store.materialsFailed("original mixed GPU cause", revision: revision)
        XCTAssertNil(store.sourceBakedMesh)
        XCTAssertNotNil(store.mesh)
        XCTAssertTrue(store.canSave)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.materialIssue, "original mixed GPU cause")
        XCTAssertNotNil(store.previewCompatibilityWarning)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        store.retryMaterials()
        await store.materialGeneration?.value
        XCTAssertNotNil(store.sourceBakedMesh)
        XCTAssertNil(store.materialIssue)
    }

    func testMixedEditingUndoRedoAndReopenPreserveExactHistoryAndAssets() async throws {
        let bytes = try source()
        let original = try Dust3DDocument(data: bytes)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: bytes)
        await settle(store)
        let node = try XCTUnwrap(store.snapshot?.nodes.first { $0.partID == Self.proceduralPart })
        store.select(node.id)
        await settle(store)
        store.isWireframe = true
        let camera = store.cameraReset
        var saved: Data?
        store.onDocumentChanged = { saved = $0 }
        store.move(
            id: node.id,
            to: NodePosition(x: node.value.position.x + 0.1, y: node.value.position.y, z: node.value.position.z))
        await settle(store)
        let edited = try XCTUnwrap(saved)
        XCTAssertNotEqual(edited, bytes)
        XCTAssertTrue(store.canUndo)
        XCTAssertNotNil(store.sourceBakedMesh)
        XCTAssertEqual(store.snapshot?.selectedID, node.id)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertTrue(store.isWireframe)
        try assertAssets(edited, original: original)
        store.undo()
        await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        XCTAssertNotNil(store.sourceBakedMesh)
        store.redo()
        await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), edited)
        let reopened = EditorStore()
        defer { reopened.stop() }
        await reopened.load(data: edited)
        await settle(reopened)
        XCTAssertNotNil(reopened.sourceBakedMesh)
        XCTAssertEqual(reopened.snapshot?.document.encoded(), edited)
        try assertAssets(try XCTUnwrap(reopened.snapshot?.document.encoded()), original: original)
    }

    func testMaterialOnlyEditRefreshesMixedMapsWithoutResettingGeometrySelectionOrCamera() async throws {
        let bytes = try source()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: bytes)
        await settle(store)
        let node = try XCTUnwrap(store.snapshot?.nodes.first { $0.partID == Self.proceduralPart })
        store.select(node.id)
        await settle(store)
        let geometryRevision = store.previewRevision
        let materialRevision = store.materialViewportRevision
        let pixels = try XCTUnwrap(store.sourceBakedMesh?.textures.metallic).pixels
        let camera = store.cameraReset
        store.setPartMaterial(Self.proceduralPart, property: .metallic, value: "0.5")
        await settle(store)
        XCTAssertEqual(store.previewRevision, geometryRevision)
        XCTAssertGreaterThan(store.materialViewportRevision, materialRevision)
        XCTAssertNotEqual(store.sourceBakedMesh?.textures.metallic?.pixels, pixels)
        XCTAssertEqual(store.snapshot?.selectedID, node.id)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertTrue(store.canUndo)
        store.undo()
        await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        XCTAssertEqual(store.sourceBakedMesh?.textures.metallic?.pixels, pixels)
    }

    func testRejectsObsoleteSourceBakesAcrossReplacementStopAndEmptyOutput() async throws {
        let bytes = try source()
        let output = try await prepared(bytes)
        let baker = SuspendedEditorSourceBaker()
        let store = EditorStore(sourceMaterialBaker: baker)
        defer { store.stop() }
        await store.load(data: bytes)
        await store.generation?.value
        try await requests(1, baker)
        let obsolete = try XCTUnwrap(store.materialGeneration)
        await store.load(data: bytes)
        await store.generation?.value
        try await requests(2, baker)
        await baker.finish(1, output)
        await store.materialGeneration?.value
        let revision = store.materialViewportRevision
        await baker.fail(0, MeshLoadingError(status: 4, message: "obsolete mixed cause"))
        await obsolete.value
        XCTAssertEqual(store.materialViewportRevision, revision)
        XCTAssertNotNil(store.sourceBakedMesh)
        XCTAssertNil(store.materialIssue)
        store.retryMaterials()
        try await requests(3, baker)
        let stopped = try XCTUnwrap(store.materialGeneration)
        store.stop()
        await baker.finish(2, output)
        await stopped.value
        XCTAssertNil(store.sourceBakedMesh)
        XCTAssertFalse(store.isUpdatingMaterials)
        await store.load(data: Dust3DDocument.emptyArchive())
        await settle(store)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.sourceBakedMesh)
        XCTAssertNil(store.materialIssue)
        let inputs = await baker.inputs
        XCTAssertEqual(inputs, [bytes, bytes, bytes])
    }

    func testPreservesOriginalSourceBakeCauseAndRetriesTheUnchangedSnapshot() async throws {
        let bytes = try source()
        let baker = SuspendedEditorSourceBaker()
        let store = EditorStore(sourceMaterialBaker: baker)
        defer { store.stop() }
        await store.load(data: bytes)
        await store.generation?.value
        try await requests(1, baker)
        await baker.fail(0, MeshLoadingError(status: 4, message: "original mixed preparation cause"))
        await store.materialGeneration?.value
        XCTAssertTrue(store.materialIssue?.contains("original mixed preparation cause") == true)
        XCTAssertNotNil(store.mesh)
        XCTAssertTrue(store.canSave)
        XCTAssertFalse(store.canUndo)
        store.retryMaterials()
        try await requests(2, baker)
        await baker.finish(1, try await prepared(bytes))
        await store.materialGeneration?.value
        XCTAssertNotNil(store.sourceBakedMesh)
        XCTAssertNil(store.materialIssue)
        let inputs = await baker.inputs
        XCTAssertEqual(inputs, [bytes, bytes])
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
    }

    private static let proceduralPart = "{00000101-0000-4000-8000-000000000101}"

    private func source() throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/MixedMaterials.ds3")
        return try Data(contentsOf: url)
    }

    private func prepared(_ data: Data) async throws -> SourceBakedMesh {
        try await ArchiveSourceTextureBakingService().load(
            data: data,
            options: SourceMeshBakeOptions(
                bake: MeshBakeOptions(colorSize: 512, normalSize: 256, materialSize: 256, atlasTextureSize: 256)))
    }

    private func assertAssets(_ data: Data, original: Dust3DDocument) throws {
        let document = try Dust3DDocument(data: data)
        for name in [
            "models/{00000300-0000-4000-8000-000000000300}.glb",
            "images/{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}.png", "opaque.bin",
        ] {
            XCTAssertEqual(document.asset(named: name), original.asset(named: name), name)
        }
    }

    private func settle(_ store: EditorStore) async {
        for _ in 0..<500 where store.isWorking { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(store.isWorking)
        await store.generation?.value
        await store.materialGeneration?.value
    }

    private func requests(_ count: Int, _ baker: SuspendedEditorSourceBaker) async throws {
        for _ in 0..<500 {
            if await baker.inputs.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw EditorSourceTestFailure.requestNotEnqueued
    }
}

private enum EditorSourceTestFailure: Error { case requestNotEnqueued }

private actor SuspendedEditorSourceBaker: ArchiveSourceTextureBaking {
    private(set) var inputs: [Data] = []
    private var pending: [CheckedContinuation<SourceBakedMesh, any Error>?] = []
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        inputs.append(data)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, _ output: SourceBakedMesh) {
        pending[index]?.resume(returning: output)
        pending[index] = nil
    }
    func fail(_ index: Int, _ error: any Error) {
        pending[index]?.resume(throwing: error)
        pending[index] = nil
    }
}
