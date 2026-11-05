import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct MultiBindingNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        throw CancellationError()
    }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        throw CancellationError()
    }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}

@MainActor final class ComponentWrappingMultiBindingStoreTests: XCTestCase {
    private func store() -> EditorStore {
        let stub = MultiBindingNoNative()
        return EditorStore(preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub)
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Multi-binding Store did not settle")
    }
    private var owners: Set<String> {
        [MultiBindingFixtureFamily.garmentID, MultiBindingFixtureFamily.secondGarmentID]
    }
    func testCapturedBatchStoreActionRoutesBothOwnersWithOneUndoWindowIsolationAndAssets() async throws {
        let inputs = try MultiBindingFixtureFamily.inputs()
        let original = try XCTUnwrap(inputs["own"])
        let first = store()
        let other = store()
        defer {
            first.stop()
            other.stop()
        }
        await first.load(data: original)
        await other.load(data: original)
        try await settle(first)
        try await settle(other)
        first.selectComponents(owners)
        try await settle(first)
        let before = try XCTUnwrap(first.snapshot)
        let target = ComponentWrappingSelectionTarget(snapshot: before)
        first.componentWrappingSelectionAction(.binding(.group(MultiBindingFixtureFamily.bodyID)), target: target)()
        XCTAssertFalse(first.canEditComponentWrappingSelection(target))
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), inputs["body"])
        XCTAssertEqual(first.snapshot?.selectedComponentIDs, owners)
        XCTAssertEqual(other.snapshot?.document.encoded(), original)
        XCTAssertEqual(first.snapshot?.document.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        first.undo()
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), original)
        XCTAssertFalse(first.canUndo)
        first.redo()
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), inputs["body"])
    }
    func testRetainedBindingCallbacksRejectSelectionConstraintDocumentABAInitialBusyAndStop() async throws {
        let original = try XCTUnwrap(MultiBindingFixtureFamily.inputs()["own"])
        for change in 0..<5 {
            let value = store()
            defer { value.stop() }
            await value.load(data: original)
            try await settle(value)
            value.selectComponents(owners)
            try await settle(value)
            let target = ComponentWrappingSelectionTarget(snapshot: try XCTUnwrap(value.snapshot))
            if change == 3 { value.selectComponents(owners) }
            let action = value.componentWrappingSelectionAction(
                .binding(.group(MultiBindingFixtureFamily.bodyID)), target: target)
            switch change {
            case 0:
                value.selectComponents([MultiBindingFixtureFamily.garmentID])
                try await settle(value)
                value.selectComponents(owners)
                try await settle(value)
            case 1:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
                try await settle(value)
            case 2:
                await value.load(data: original)
                try await settle(value)
                value.selectComponents(owners)
                try await settle(value)
            case 3: try await settle(value)
            default: value.stop()
            }
            action()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original)
            XCTAssertFalse(value.canUndo)
        }
    }
    func testMixedSourceHostedControlsPreserveSourceAndExposeDisambiguatedOwnerValues() async throws {
        let original = try Dust3DDocument(data: XCTUnwrap(MultiBindingFixtureFamily.inputs()["own"]))
            .applying(
                .setComponentWrapBinding(
                    id: MultiBindingFixtureFamily.garmentID, choice: .group(MultiBindingFixtureFamily.bodyID)))
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(owners)
        try await settle(value)
        let snapshot = try XCTUnwrap(value.snapshot)
        let target = ComponentWrappingSelectionTarget(snapshot: snapshot)
        let presentation = try ComponentWrappingMultiBindingPresentation(
            groups: snapshot.selectedComponentRows.map(\.component),
            components: snapshot.componentTree.rows.map(\.component))
        XCTAssertEqual(presentation.currentTitle, "Multiple values")
        XCTAssertEqual(
            presentation.sources.map(\.owner),
            [
                "Garment: \(MultiBindingFixtureFamily.garmentID)",
                "Garment: \(MultiBindingFixtureFamily.secondGarmentID)",
            ])
        XCTAssertTrue(presentation.sources[0].value.contains(MultiBindingFixtureFamily.bodyID))
        for scheme in [ColorScheme.light, .dark] {
            let png = try InspectorRenderer.png(
                ComponentWrappingMultiBindingControls(store: value, target: target), width: 320, scheme: scheme)
            XCTAssertGreaterThan(png.count, 1000)
            if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                try png.write(
                    to: URL(fileURLWithPath: output).appendingPathComponent(
                        "multi-binding-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }
}
