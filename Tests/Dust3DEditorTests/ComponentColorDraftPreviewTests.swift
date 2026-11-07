import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

private struct ColorDraftNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

private actor HeldColorDraftPreview: ComponentColorDraftPreviewServing {
    private var pending: [String: CheckedContinuation<IndexedMesh?, any Error>] = [:]

    func generate(_ data: Data, scopeID: UUID) async throws -> IndexedMesh? {
        let document = try Dust3DDocument(data: data)
        let component = try document.components().first { $0.id == "c" }
        guard case .value(let color) = component?.color else { throw DocumentError.invalidComponentColor }
        return try await withCheckedThrowingContinuation { pending[color.archiveValue] = $0 }
    }

    func isPending(_ color: DocumentColor) -> Bool { pending[color.archiveValue] != nil }

    func complete(_ color: DocumentColor, fails: Bool = false) {
        guard let result = pending.removeValue(forKey: color.archiveValue) else { return }
        if fails {
            result.resume(throwing: DocumentError.invalidComponentColor)
        } else {
            result.resume(
                returning: IndexedMesh(
                    vertices: [], indices: [], nodeCount: 1, partCount: 1, warning: color.archiveValue))
        }
    }

    func drain() {
        let remaining = pending
        pending = [:]
        for result in remaining.values { result.resume(throwing: CancellationError()) }
    }
}

@MainActor final class ComponentColorDraftPreviewTests: XCTestCase {
    private let red = DocumentColor(red: 255, green: 0, blue: 0)
    private let blue = DocumentColor(red: 0, green: 0, blue: 255)

    private func setup(texture: Bool = false, orphanModel: Bool = false) async throws -> (
        EditorStore, HeldColorDraftPreview, Data
    ) {
        let image = texture ? " colorImageId='{11111111-1111-4111-8111-111111111111}'" : ""
        let model = Data(
            """
            <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
            <parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p'\(image)/>
            </components></canvas>
            """.utf8)
        let original: Data
        if orphanModel {
            let prefix = "DUST3D 1.0 xml "
            let header = """
                <ds3><model name='model.xml' offset='0' size='\(model.count)'/>
                <asset name=' models/orphan.glb ' offset='\(model.count)' size='1'/></ds3>
                """
            original =
                Data(
                    (prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0])
        } else {
            original = try Dust3DDocument(snapshotXML: model).encoded()
        }
        let stub = ColorDraftNoNative()
        let preview = HeldColorDraftPreview()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub, colorDraftPreview: preview)
        await store.load(data: original)
        store.selectComponent("c")
        try await settle { !store.isWorking }
        return (store, preview, original)
    }

    private func settle(_ predicate: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Draft preview did not settle")
    }

    func testOnlyLatestDraftAppearsAndExplicitApplyIsOneExactUndo() async throws {
        let (store, preview, original) = try await setup()
        defer {
            store.stop()
            Task { await preview.drain() }
        }
        let target = try XCTUnwrap(store.componentColorDraftPreviewTarget(componentID: "c"))
        let priorRevision = store.previewRevision
        store.startComponentColorDraftPreview(red, target: target)
        try await settle { await preview.isPending(self.red) }
        store.updateComponentColorDraftPreview(blue, target: target)
        try await settle { await preview.isPending(self.blue) }
        await preview.complete(blue)
        try await settle { store.componentColorDraftMesh?.warning == self.blue.archiveValue }
        await preview.complete(red)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(store.componentColorDraftMesh?.warning, blue.archiveValue)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertEqual(store.previewRevision, priorRevision)
        XCTAssertNil(store.materialContent)
        XCTAssertFalse(store.canUndo)

        store.setComponentColor("c", value: blue.archiveValue)
        try await settle { !store.isWorking }
        XCTAssertNil(store.componentColorDraftMesh)
        XCTAssertTrue(store.canUndo)
        store.undo()
        try await settle { !store.isWorking }
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testFailedReplacementCancelAndTexturedSourceCannotPublishDraft() async throws {
        let (store, preview, original) = try await setup()
        defer {
            store.stop()
            Task { await preview.drain() }
        }
        let target = try XCTUnwrap(store.componentColorDraftPreviewTarget(componentID: "c"))
        store.startComponentColorDraftPreview(red, target: target)
        try await settle { await preview.isPending(self.red) }
        store.stopComponentColorDraftPreview(target: target)
        await preview.complete(red)
        XCTAssertNil(store.componentColorDraftMesh)

        store.startComponentColorDraftPreview(blue, target: target)
        try await settle { await preview.isPending(self.blue) }
        await store.load(data: Data("invalid archive".utf8))
        await preview.complete(blue)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertNil(store.componentColorDraftMesh)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
        XCTAssertNil(store.componentColorDraftPreviewTarget(componentID: "c"))

        let (textured, texturedPreview, _) = try await setup(texture: true)
        defer {
            textured.stop()
            Task { await texturedPreview.drain() }
        }
        XCTAssertNil(textured.componentColorDraftPreviewTarget(componentID: "c"))
    }
    func testCurrentGenerationAndRenderFailuresLeaveCommittedStateUntouched() async throws {
        let (store, preview, original) = try await setup()
        defer {
            store.stop()
            Task { await preview.drain() }
        }
        let target = try XCTUnwrap(store.componentColorDraftPreviewTarget(componentID: "c"))
        let committedError = store.renderError
        store.startComponentColorDraftPreview(red, target: target)
        try await settle { await preview.isPending(self.red) }
        await preview.complete(red, fails: true)
        try await settle { store.componentColorDraftPreviewMessage != "Updating color draft…" }
        XCTAssertNotNil(store.componentColorDraftPreviewMessage)
        XCTAssertNil(store.componentColorDraftMesh)
        store.updateComponentColorDraftPreview(blue, target: target)
        try await settle { await preview.isPending(self.blue) }
        await preview.complete(blue)
        try await settle { store.componentColorDraftMesh != nil }
        let revision = store.componentColorDraftRevision
        store.colorDraftRenderFailed("obsolete", revision: revision - 1)
        XCTAssertNotNil(store.componentColorDraftMesh)
        store.colorDraftRenderFailed("draft renderer failed", revision: revision)
        XCTAssertNil(store.componentColorDraftMesh)
        XCTAssertEqual(store.componentColorDraftPreviewMessage, "draft renderer failed")
        XCTAssertEqual(store.renderError, committedError)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testOrphanModelAssetRejectsDraftBeforePreviewSubmission() async throws {
        let (store, preview, original) = try await setup(orphanModel: true)
        defer {
            store.stop()
            Task { await preview.drain() }
        }
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertNil(store.componentColorDraftPreviewTarget(componentID: "c"))
    }

}
