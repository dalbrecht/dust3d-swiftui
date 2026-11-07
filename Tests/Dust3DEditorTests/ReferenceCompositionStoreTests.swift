import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import XCTest

@testable import Dust3DEditor

final class ReferenceCompositionStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Reference composition commit did not settle")
    }
    @MainActor func testApplyCompletionPreviewUndoStaleAndStoppedTargets() async throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let source = try ReferenceCompositionSource(image: image, crop: .init(size: .init(width: 1, height: 1)))
        let result = try ReferenceCompositionRaster.compose(front: source, side: nil)
        let original = Dust3DDocument.emptyArchive()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original)
        try await settle(store)
        let target = ReferenceCompositionTarget(snapshot: try XCTUnwrap(store.snapshot))
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }
        let success = await store.applyReferenceComposition(result, target: target, setsOrigin: true)
        XCTAssertTrue(success)
        try await settle(store)
        XCTAssertNotNil(store.referenceImage)
        XCTAssertEqual(store.snapshot?.origin, result.layout.origin)
        XCTAssertEqual(writes.count, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertNil(store.referenceImage)
        let failed = await store.applyReferenceComposition(result, target: target, setsOrigin: false)
        XCTAssertFalse(failed)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.canRedo)
        XCTAssertEqual(writes.count, 2)
        let latest = ReferenceCompositionTarget(snapshot: try XCTUnwrap(store.snapshot))
        store.stop()
        let stopped = await store.applyReferenceComposition(result, target: latest, setsOrigin: false)
        XCTAssertFalse(stopped)
    }
}

private struct ReferenceCompositionNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor
final class ReferenceCompositionSourceAdmissionTests: XCTestCase {
    func testFailedReloadRetainsSnapshotButRejectsComposerAndApply() async throws {
        let stub = ReferenceCompositionNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
        defer { store.stop() }
        let original = Dust3DDocument.emptyArchive()
        await store.load(data: original)
        let target = try XCTUnwrap(store.referenceCompositionTarget)
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let source = try ReferenceCompositionSource(image: image, crop: .init(size: .init(width: 1, height: 1)))
        let result = try ReferenceCompositionRaster.compose(front: source, side: nil)
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }

        await store.load(data: Data("invalid archive".utf8), fileIdentity: UUID())

        XCTAssertTrue(store.canSave)
        XCTAssertNil(store.referenceCompositionTarget)
        let applied = await store.applyReferenceComposition(result, target: target, setsOrigin: true)
        XCTAssertFalse(applied)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertFalse(store.canUndo)

        await store.load(data: original)
        let reopened = try XCTUnwrap(store.referenceCompositionTarget)
        let appliedAfterReopen = await store.applyReferenceComposition(result, target: reopened, setsOrigin: true)
        XCTAssertTrue(appliedAfterReopen)
        XCTAssertEqual(writes.count, 1)
    }
}
