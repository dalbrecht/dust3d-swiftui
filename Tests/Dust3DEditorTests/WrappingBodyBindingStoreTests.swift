import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

/// Block every native material/preview route while testing store admission and publication.
private struct BodyBindingNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class WrappingBodyBindingStoreTests: XCTestCase {
    private func store() -> EditorStore {
        let boundary = BodyBindingNoNative()
        return EditorStore(
            preview: boundary, materialBaker: boundary, importedMaterialLoader: boundary, sourceMaterialBaker: boundary)
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials && !store.isLoadingReferenceImage {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Body-binding store did not settle")
    }
    func testCapturedStoreActionRoutesOneUndoPreservesOtherWindowAndExactAssets() async throws {
        let inputs = try BodyBindingFixtureFamily.inputs()
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
        first.selectComponent(BodyBindingFixtureFamily.garmentID)
        try await settle(first)
        let before = try XCTUnwrap(first.snapshot)
        let target = ComponentWrapBindingTarget(snapshot: before)
        XCTAssertTrue(first.canEditComponentWrapBinding(target))
        first.componentWrapBindingAction(.group(BodyBindingFixtureFamily.bodyID), target: target)()
        XCTAssertFalse(first.canEditComponentWrapBinding(target))
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), inputs["body"])
        XCTAssertEqual(first.snapshot?.selectedComponentID, BodyBindingFixtureFamily.garmentID)
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
    func testRetainedCallbacksRejectReplacementConstraintAwayBackBusyAndStop() async throws {
        let original = try XCTUnwrap(BodyBindingFixtureFamily.inputs()["own"])
        for change in 0..<4 {
            let value = store()
            defer { value.stop() }
            await value.load(data: original)
            try await settle(value)
            value.selectComponent(BodyBindingFixtureFamily.garmentID)
            try await settle(value)
            let target = ComponentWrapBindingTarget(snapshot: try XCTUnwrap(value.snapshot))
            let action: @MainActor () -> Void
            if change == 2 {
                value.selectComponent(BodyBindingFixtureFamily.garmentID)
                action = value.componentWrapBindingAction(.group(BodyBindingFixtureFamily.bodyID), target: target)
                try await settle(value)
            } else {
                action = value.componentWrapBindingAction(.group(BodyBindingFixtureFamily.bodyID), target: target)
            }
            switch change {
            case 0:
                await value.load(data: original)
                try await settle(value)
                value.selectComponent(BodyBindingFixtureFamily.garmentID)
                try await settle(value)
            case 1:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
                try await settle(value)
            case 3: value.stop()
            default: break
            }
            action()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original)
            XCTAssertFalse(value.canUndo)
        }
    }
    func testHostedBindingPickerRendersBothAppearancesWithoutCallingNativeServices() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try XCTUnwrap(BodyBindingFixtureFamily.inputs()["body"]))
        try await settle(value)
        value.selectComponent(BodyBindingFixtureFamily.garmentID)
        try await settle(value)
        let component = try XCTUnwrap(value.snapshot?.selectedComponent)
        for scheme in [ColorScheme.light, .dark] {
            let png = try InspectorRenderer.png(
                ComponentWrapBindingControls(store: value, component: component), width: 290, scheme: scheme)
            XCTAssertGreaterThan(png.count, 1000)
            if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                try png.write(
                    to: URL(fileURLWithPath: output).appendingPathComponent(
                        "wrapping-body-binding-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    func testOldComponentViewCannotAcquireNewlySelectedGroupTarget() async throws {
        var document = try Dust3DDocument(data: XCTUnwrap(BodyBindingFixtureFamily.inputs()["own"]))
        document = try document.applying(.setComponentWrapMode(id: BodyBindingFixtureFamily.bodyID, mode: .skin))
        let value = store()
        defer { value.stop() }
        await value.load(data: document.encoded())
        try await settle(value)
        value.selectComponent(BodyBindingFixtureFamily.garmentID)
        try await settle(value)
        let old = try XCTUnwrap(value.snapshot?.selectedComponent)
        value.selectComponent(BodyBindingFixtureFamily.bodyID)
        try await settle(value)
        let snapshot = try XCTUnwrap(value.snapshot)
        XCTAssertNil(ComponentWrapBindingPresentation.current(component: old, snapshot: snapshot))
        XCTAssertNotNil(
            ComponentWrapBindingPresentation.current(
                component: try XCTUnwrap(snapshot.selectedComponent), snapshot: snapshot))
        XCTAssertFalse(value.canUndo)
    }

}
