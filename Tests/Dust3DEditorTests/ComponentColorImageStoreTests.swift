import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private actor DelayedColorImages: ColorImageServing {
    private var pending: [CheckedContinuation<Data, any Error>?] = []
    var count: Int { pending.count }
    enum Failure: LocalizedError {
        case rejected
        var errorDescription: String? { "Original image decoding cause" }
    }
    func importImage(url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func validateRetainedImage(document: Dust3DDocument, asset: DocumentColorImageAsset) {}
    func finish(_ data: Data, index: Int = 0) {
        pending[index]?.resume(returning: data)
        pending[index] = nil
    }
    func fail(index: Int = 0) {
        pending[index]?.resume(throwing: Failure.rejected)
        pending[index] = nil
    }
}

private struct GraphTextureNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

private actor RecordingTextureActions: ColorImageServing {
    let png: Data
    private(set) var importedURLs: [URL] = []
    private(set) var assignments = 0

    init(png: Data) { self.png = png }

    func importImage(url: URL) async throws -> Data {
        importedURLs.append(url)
        return png
    }

    func validateRetainedImage(document: Dust3DDocument, asset: DocumentColorImageAsset) {
        assignments += 1
    }
}

private actor HeldColorImageInspection {
    private var pending: CheckedContinuation<CGImage, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func load() async -> CGImage {
        await withCheckedContinuation { continuation in
            pending = continuation
            waiter?.resume()
            waiter = nil
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release(_ image: CGImage) {
        pending?.resume(returning: image)
        pending = nil
    }
}

@MainActor
final class ComponentColorImageStoreTests: XCTestCase {
    private let component = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}",
                partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", componentID: component,
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
    }
    private var png: Data {
        get throws {
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
                ))
        }
    }
    private func ready(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating && !store.isPreparingColorImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Image operation did not settle")
    }
    private func start(_ store: EditorStore, service: DelayedColorImages, expectedRequests: Int = 1) async throws
        -> Task<Void, Never>
    {
        let target = try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)))
        store.importComponentColorImage(url: URL(fileURLWithPath: "/unused.png"), target: target)
        let request = try XCTUnwrap(store.colorImagePreparation)
        for _ in 0..<500 {
            if await service.count >= expectedRequests { return request }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Import did not start")
        return request
    }

    private let otherComponent = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
    private let imageURL = URL(fileURLWithPath: "/unused.png")

    private func twoTextureOwners() throws -> Dust3DDocument {
        try document().applying(
            .addNode(
                id: "{22222222-2222-4222-8222-222222222222}",
                partID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", componentID: otherComponent,
                position: .init(x: 0.7, y: 0.5, z: 0.5), radius: 0.1)
        )
        .applying(
            .importComponentColorImage(
                id: component, imageID: "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}", png: png))
    }

    private func inertTextureStore(service: RecordingTextureActions) -> EditorStore {
        let stub = GraphTextureNoNative()
        return EditorStore(
            colorImages: service, preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }

    func testRenderedImageActionsRejectDifferentAndRoundTripSelectionBeforeImageWork() async throws {
        let source = try twoTextureOwners()
        let service = RecordingTextureActions(png: try png)
        let store = inertTextureStore(service: service)
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponent(component)
        try await ready(store)
        let rendered = try XCTUnwrap(store.componentColorImageDestination(componentID: component))
        let asset = try XCTUnwrap(store.snapshot?.colorImageAssets.first)

        for selected in [otherComponent, component] {
            store.selectComponent(selected)
            try await ready(store)
            XCTAssertNil(
                store.componentColorImageDestination(componentID: selected == component ? otherComponent : component))
            store.chooseComponentColorImage(destination: rendered)
            XCTAssertNil(store.componentColorImageChoiceRequestID)
            store.assignComponentColorImage(asset, destination: rendered)
            store.clearComponentColorImage(destination: rendered)
            try await ready(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
            XCTAssertFalse(store.canUndo)
        }
        let importedURLs = await service.importedURLs
        let assignments = await service.assignments
        XCTAssertTrue(importedURLs.isEmpty)
        XCTAssertEqual(assignments, 0)
    }

    func testPickerCancellationAndLateCallbacksCannotClearNewRequest() async throws {
        let source = try twoTextureOwners()
        let service = RecordingTextureActions(png: try png)
        let store = inertTextureStore(service: service)
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponent(component)
        try await ready(store)
        let oldDestination = try XCTUnwrap(store.componentColorImageDestination(componentID: component))
        store.chooseComponentColorImage(destination: oldDestination)
        let old = try XCTUnwrap(store.componentColorImageChoiceRequestID)
        store.chooseComponentColorImage(destination: oldDestination)
        XCTAssertEqual(store.componentColorImageChoiceRequestID, old)
        store.cancelComponentColorImageChoice(requestID: old)

        store.selectComponent(otherComponent)
        try await ready(store)
        let newDestination = try XCTUnwrap(store.componentColorImageDestination(componentID: otherComponent))
        store.chooseComponentColorImage(destination: newDestination)
        let current = try XCTUnwrap(store.componentColorImageChoiceRequestID)
        XCTAssertNotEqual(current, old)
        store.finishComponentColorImageChoice(requestID: old, result: .success([imageURL]))
        store.finishComponentColorImageChoice(requestID: old, result: .failure(DelayedColorImages.Failure.rejected))
        store.cancelComponentColorImageChoice(requestID: old)
        XCTAssertEqual(store.componentColorImageChoiceRequestID, current)
        XCTAssertNil(store.errorMessage)

        store.finishComponentColorImageChoice(requestID: current, result: .success([imageURL]))
        try await ready(store)
        let importedURLs = await service.importedURLs
        XCTAssertEqual(importedURLs, [imageURL])
        XCTAssertNil(store.componentColorImageChoiceRequestID)
        XCTAssertEqual(store.snapshot?.selectedComponentID, otherComponent)
        XCTAssertNotEqual(store.snapshot?.selectedComponent?.colorImage, .some(.unset))
        XCTAssertEqual(store.snapshot?.colorImageAssets.count, 2)
        XCTAssertTrue(store.canUndo)
        store.undo()
        try await ready(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testPickerRejectsSelectionABAAndReplacementBeforeDecode() async throws {
        let source = try twoTextureOwners()
        let service = RecordingTextureActions(png: try png)
        let store = inertTextureStore(service: service)
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponent(component)
        try await ready(store)
        let destination = try XCTUnwrap(store.componentColorImageDestination(componentID: component))
        store.chooseComponentColorImage(destination: destination)
        let request = try XCTUnwrap(store.componentColorImageChoiceRequestID)
        store.selectComponent(otherComponent)
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        store.finishComponentColorImageChoice(requestID: request, result: .success([imageURL]))
        try await ready(store)
        XCTAssertNil(store.componentColorImageChoiceRequestID)

        let fresh = try XCTUnwrap(store.componentColorImageDestination(componentID: component))
        store.chooseComponentColorImage(destination: fresh)
        let replaced = try XCTUnwrap(store.componentColorImageChoiceRequestID)
        await store.load(data: source.encoded())
        try await ready(store)
        XCTAssertNil(store.componentColorImageChoiceRequestID)
        store.finishComponentColorImageChoice(requestID: replaced, result: .success([imageURL]))
        let importedURLs = await service.importedURLs
        XCTAssertTrue(importedURLs.isEmpty)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testAppliedAndRetainedTextureInspectionDoesNotAssignOrWrite() async throws {
        let original = try document().applying(
            .importComponentColorImage(id: component, imageID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd", png: png))
        let retainedOnly = try original.applying(.setComponentColorImage(id: component, imageID: nil))
        let stub = GraphTextureNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        for useApplied in [true, false] {
            let source = useApplied ? original : retainedOnly
            await store.load(data: source.encoded())
            store.select(try XCTUnwrap(store.snapshot?.nodes.first?.id))
            try await ready(store)
            let before = try XCTUnwrap(store.snapshot)
            let destination = EditorStore.ComponentColorImageDestination.graph(
                ComponentMeshSelectionTarget(graphSelection: before))
            let asset = try XCTUnwrap(before.colorImageAssets.first)
            if !useApplied {
                XCTAssertNil(store.componentColorImageInspectionRequest(asset: nil, destination: destination))
            }
            let request = try XCTUnwrap(
                store.componentColorImageInspectionRequest(asset: useApplied ? nil : asset, destination: destination))
            XCTAssertEqual(request.asset, asset)
            let inspection = ComponentColorImageInspection()
            var writes = 0
            store.onDocumentChanged = { _ in writes += 1 }
            let task = try XCTUnwrap(
                inspection.inspect(request, isCurrent: { store.canInspectComponentColorImage(request) }))
            await task.value
            XCTAssertEqual(inspection.image?.width, 2)
            XCTAssertEqual(inspection.image?.height, 1)
            XCTAssertNil(inspection.errorMessage)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
            XCTAssertEqual(store.snapshot?.previewIdentity, before.previewIdentity)
            XCTAssertEqual(store.snapshot?.selectedIDs, before.selectedIDs)
            XCTAssertFalse(store.canUndo)
            XCTAssertEqual(writes, 0)
        }
    }

    func testHeldTextureInspectionRejectsSelectionABAAndFailedSource() async throws {
        let source = try document().applying(
            .importComponentColorImage(id: component, imageID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd", png: png))
        let stub = GraphTextureNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        for replaceSource in [false, true] {
            await store.load(data: source.encoded())
            store.selectComponent(component)
            try await ready(store)
            let destination = EditorStore.ComponentColorImageDestination.component(
                try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:))))
            let request = try XCTUnwrap(
                store.componentColorImageInspectionRequest(asset: nil, destination: destination))
            let gate = HeldColorImageInspection()
            let inspection = ComponentColorImageInspection(load: { _ in await gate.load() })
            let task = try XCTUnwrap(
                inspection.inspect(request, isCurrent: { store.canInspectComponentColorImage(request) }))
            await gate.waitUntilStarted()
            if replaceSource {
                await store.load(data: Data("bad archive".utf8))
            } else {
                store.selectComponent(nil)
                try await ready(store)
                store.selectComponent(component)
                try await ready(store)
            }
            XCTAssertFalse(store.canInspectComponentColorImage(request))
            await gate.release(try ColorImageCodec.previewPNG(png))
            await task.value
            XCTAssertNil(inspection.image)
            XCTAssertNil(inspection.errorMessage)
            XCTAssertFalse(inspection.isLoading)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
            XCTAssertFalse(store.canUndo)
        }
    }

    func testGraphTextureRejectsPreparedResultAfterFailedReplacement() async throws {
        let source = try document()
        let service = DelayedColorImages()
        let stub = GraphTextureNoNative()
        let store = EditorStore(
            colorImages: service, preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.select(try XCTUnwrap(store.snapshot?.nodes.first?.id))
        try await ready(store)
        let target = ComponentMeshSelectionTarget(graphSelection: try XCTUnwrap(store.snapshot))
        store.importComponentColorImage(url: URL(fileURLWithPath: "/unused.png"), destination: .graph(target))
        let task = try XCTUnwrap(store.colorImagePreparation)
        for _ in 0..<500 {
            if await service.count == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let count = await service.count
        guard count == 1 else { return XCTFail("Graph image preparation did not start") }
        await store.load(data: Data("invalid archive".utf8))
        let loadError = try XCTUnwrap(store.errorMessage)
        await service.finish(try png)
        await task.value
        store.clearComponentColorImage(destination: .graph(target))
        XCTAssertEqual(store.errorMessage, loadError)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.isPreparingColorImage)

        await store.load(data: source.encoded())
        store.select(try XCTUnwrap(store.snapshot?.nodes.first?.id))
        try await ready(store)
        let recovered = ComponentMeshSelectionTarget(graphSelection: try XCTUnwrap(store.snapshot))
        store.importComponentColorImage(url: URL(fileURLWithPath: "/unused.png"), destination: .graph(recovered))
        let next = try XCTUnwrap(store.colorImagePreparation)
        for _ in 0..<500 {
            if await service.count == 2 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        guard await service.count == 2 else { return XCTFail("Recovered graph image preparation did not start") }
        await service.finish(try png, index: 1)
        await next.value
        try await ready(store)
        XCTAssertEqual(store.snapshot?.colorImageAssets.count, 1)
        XCTAssertTrue(store.canUndo)
    }

    func testImportPublishesOneHistoryStepWithoutRegeneratingGeometry() async throws {
        let source = try document()
        let service = DelayedColorImages()
        let store = EditorStore(colorImages: service)
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        let revision = store.previewRevision
        let request = try await start(store, service: service)
        XCTAssertTrue(store.canSave)
        XCTAssertFalse(store.isWorking)
        await service.finish(try png)
        await request.value
        try await ready(store)
        XCTAssertEqual(store.snapshot?.colorImageAssets.count, 1)
        XCTAssertEqual(store.previewRevision, revision)
        let imported = store.snapshot?.document.encoded()
        store.undo()
        try await ready(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.redo()
        try await ready(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), imported)
    }

    func testCancelledPreparationCannotPublishAfterSelectionChangesAwayAndBack() async throws {
        let source = try document()
        let service = DelayedColorImages()
        let store = EditorStore(colorImages: service)
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        let request = try await start(store, service: service)
        store.clearComponentSelection()
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        await service.finish(try png)
        await request.value
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.snapshot?.canUndo ?? true)
    }

    func testRetainedAssignmentAndClearPreserveAssetBytesAndExactHistory() async throws {
        let imported = try document().applying(
            .importComponentColorImage(id: component, imageID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd", png: png))
        let source = try imported.applying(.setComponentColorImage(id: component, imageID: nil))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        let target = try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)))
        let asset = try XCTUnwrap(store.snapshot?.colorImageAssets.first)
        let revision = store.previewRevision
        store.assignComponentColorImage(asset, target: target)
        try await ready(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(
            store.snapshot?.selectedComponent?.colorImage, .reference("{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"))
        XCTAssertEqual(store.snapshot?.document.asset(named: asset.assetName), try png)
        let assigned = store.snapshot?.document.encoded()
        store.undo()
        try await ready(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.redo()
        try await ready(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), assigned)
        let fresh = try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)))
        store.clearComponentColorImage(target: fresh)
        try await ready(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.colorImage, .unset)
        XCTAssertEqual(store.snapshot?.document.asset(named: asset.assetName), try png)
        XCTAssertEqual(
            try Dust3DDocument(data: XCTUnwrap(store.snapshot?.document.encoded())).colorImageAssets(), [asset])
        store.undo()
        try await ready(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), assigned)
    }

    func testAssignedImageChangesRealBakedOutputAndSurvivesSaveReopen() async throws {
        let source = try document()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try png.write(to: url)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        await store.generation?.value
        await store.materialGeneration?.value
        let before = try XCTUnwrap(store.bakedMesh?.textures.color.pixels)
        store.selectComponent(component)
        try await ready(store)
        let target = try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)))
        store.importComponentColorImage(url: url, target: target)
        await store.colorImagePreparation?.value
        try await ready(store)
        await store.materialGeneration?.value
        XCTAssertNil(store.materialIssue)
        let after = try XCTUnwrap(store.bakedMesh?.textures.color.pixels)
        XCTAssertNotEqual(before, after)
        XCTAssertNotNil(store.previewCompatibilityWarning, "CPU preparation does not acknowledge a displayed GPU frame")
        let materialRevision = store.materialViewportRevision
        store.materialsRendered(revision: materialRevision - 1)
        XCTAssertNotNil(store.previewCompatibilityWarning, "An obsolete GPU receipt cannot clear the current notice")
        store.materialsRendered(revision: materialRevision)
        XCTAssertNil(store.previewCompatibilityWarning)
        let encoded = try XCTUnwrap(store.snapshot?.document.encoded())
        let reopened = try Dust3DDocument(data: encoded)
        let asset = try XCTUnwrap(reopened.colorImageAssets().first)
        XCTAssertEqual(reopened.asset(named: asset.assetName), try png)
        await store.load(data: encoded)
        await store.generation?.value
        await store.materialGeneration?.value
        XCTAssertEqual(store.bakedMesh?.textures.color.pixels, after)
        XCTAssertEqual(store.snapshot?.document.encoded(), encoded)
    }

    func testSharedRetainedImageRemainsWhenOneComponentOverrideIsCleared() async throws {
        let other = "{ffffffff-ffff-4fff-8fff-ffffffffffff}"
        let source = try document().applying(
            .addNode(
                id: "{22222222-2222-4222-8222-222222222222}",
                partID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", componentID: other,
                position: .init(x: 0.7, y: 0.5, z: 0.5), radius: 0.1)
        )
        .applying(.importComponentColorImage(id: component, imageID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd", png: png))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await ready(store)
        store.selectComponent(other)
        try await ready(store)
        let target = try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)))
        let asset = try XCTUnwrap(store.snapshot?.colorImageAssets.first)
        store.assignComponentColorImage(asset, target: target)
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        let clear = try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)))
        store.clearComponentColorImage(target: clear)
        try await ready(store)
        XCTAssertEqual(store.snapshot?.colorImageAssets, [asset])
        XCTAssertEqual(store.snapshot?.document.asset(named: asset.assetName), try png)
        let components = try XCTUnwrap(store.snapshot?.document.components())
        XCTAssertEqual(components.first(where: { $0.id == component })?.colorImage, .unset)
        XCTAssertEqual(
            components.first(where: { $0.id == other })?.colorImage,
            .reference("{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"))
    }

    func testMalformedRetainedImageCannotChangeDocumentOrHistory() async throws {
        var corrupt = try png
        let marker = try XCTUnwrap(corrupt.range(of: Data("IDAT".utf8)))
        corrupt[marker.upperBound] = 0
        corrupt[marker.upperBound + 1] = 0
        let source = try document().applying(
            .importComponentColorImage(id: component, imageID: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", png: corrupt)
        )
        .applying(.setComponentColorImage(id: component, imageID: nil))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        let target = try XCTUnwrap(store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)))
        store.assignComponentColorImage(try XCTUnwrap(store.snapshot?.colorImageAssets.first), target: target)
        try await ready(store)
        XCTAssertTrue(store.errorMessage?.contains("images/{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}.png") == true)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testNewImportSupersedesLateEarlierResultAndStopDiscardsLateFailure() async throws {
        let source = try document()
        let service = DelayedColorImages()
        let store = EditorStore(colorImages: service)
        await store.load(data: source.encoded())
        try await ready(store)
        store.selectComponent(component)
        try await ready(store)
        let first = try await start(store, service: service)
        let second = try await start(store, service: service, expectedRequests: 2)
        await service.finish(try png, index: 1)
        await second.value
        try await ready(store)
        let imported = store.snapshot?.document.encoded()
        await service.fail(index: 0)
        await first.value
        XCTAssertEqual(store.snapshot?.document.encoded(), imported)
        XCTAssertNil(store.errorMessage)
        let third = try await start(store, service: service, expectedRequests: 3)
        store.stop()
        await service.fail(index: 2)
        await third.value
        XCTAssertFalse(store.isPreparingColorImage)
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.document.encoded(), imported)
    }

    func testReplacementAndExplicitCancellationRejectLateImportCompletions() async throws {
        for replacement in [false, true] {
            let source = try document()
            let service = DelayedColorImages()
            let store = EditorStore(colorImages: service)
            await store.load(data: source.encoded())
            try await ready(store)
            store.selectComponent(component)
            try await ready(store)
            let request = try await start(store, service: service)
            if replacement { await store.load(data: source.encoded()) } else { store.cancelColorImagePreparation() }
            await service.finish(try png)
            await request.value
            try await ready(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
            XCTAssertFalse(store.snapshot?.canUndo ?? true)
            XCTAssertNil(store.errorMessage)
            store.stop()
        }
    }
}
