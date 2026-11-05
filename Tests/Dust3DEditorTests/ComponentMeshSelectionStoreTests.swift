import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct MeshSettingsNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
@MainActor final class ComponentMeshSelectionStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='p' target='CutFace' locked='true' visible='false' disabled='true'/></parts><components><component id='a' inverse='true' smoothCutoffDegrees='090.00' linkDataType='partId' linkData='p'/><component id='b' combineMode='Future' smoothCutoffDegrees='future'/></components></canvas>"
                    .utf8))
    }
    private func store() -> EditorStore {
        let stub = MeshSettingsNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Store did not settle")
    }
    func testCombineCurrentStatusAndAccessibilityKeepFullUnsupportedValueAndSelectionCount() {
        XCTAssertEqual(
            ComponentMeshFieldPresentation.title(
                ComponentMeshSelectionValue<ComponentCombineMode>.unsupported, render: { $0.rawValue }),
            "Unsupported source value")
        XCTAssertEqual(
            ComponentMeshFieldPresentation.combineAccessibilityLabel(count: 2),
            "Change combine mode for 2 selected components")
        XCTAssertEqual(
            ComponentMeshFieldPresentation.combineAccessibilityValue(.unsupported, count: 2),
            "Unsupported source value; 2 selected components")
        XCTAssertEqual(
            ComponentMeshFieldPresentation.combineAccessibilityValue(.mixed, count: 3),
            "Multiple values; 3 selected components")
        XCTAssertEqual(
            ComponentMeshFieldPresentation.combineAccessibilityValue(.uniform(.inversion), count: 2),
            "Inversion; 2 selected components")
    }
    func testActualBatchActionPublishesOncePreservesFlagsSelectionAndOtherWindowWithExactUndo() async throws {
        let original = try source()
        let value = store()
        let other = store()
        defer {
            value.stop()
            other.stop()
        }
        await value.load(data: original.encoded())
        await other.load(data: original.encoded())
        try await settle(value)
        try await settle(other)
        value.selectComponents(["a", "b"])
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        let target = ComponentMeshSelectionTarget(snapshot: before)
        XCTAssertTrue(value.canEditComponentMeshSettings(target))
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        value.componentMeshAction(.combineMode(.uncombined), target: target)()
        try await settle(value)
        XCTAssertEqual(publications, 1)
        XCTAssertTrue(
            value.snapshot?.selectedComponentRows.allSatisfy { $0.component.combineMode == .uncombined } == true)
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(value.snapshot?.parts, before.parts)
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }
    func testRetainedActionsRejectSelectionConstraintReplacementABAInitialBusyAndStopped() async throws {
        for change in 0..<5 {
            let value = store()
            defer { value.stop() }
            let original = try source()
            await value.load(data: original.encoded())
            try await settle(value)
            value.selectComponents(["a", "b"])
            try await settle(value)
            let target = ComponentMeshSelectionTarget(snapshot: try XCTUnwrap(value.snapshot))
            if change == 3 { value.selectComponents(["a", "b"]) }
            let action = value.componentMeshAction(.combineMode(.normal), target: target)
            switch change {
            case 0:
                value.selectComponents(["a"])
                try await settle(value)
                value.selectComponents(["a", "b"])
            case 1:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
            case 2: await value.load(data: original.encoded())
            case 3: break
            default: value.stop()
            }
            try await settle(value)
            action()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(value.canUndo)
        }
    }
    func testInvalidDraftNeverAppliesOldValueAndValidatedActionUsesCapturedText() async throws {
        let value = store()
        defer { value.stop() }
        let original = try source()
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(["a", "b"])
        try await settle(value)
        let target = ComponentMeshSelectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        for text in ["", "-", "oops", "nan", "inf", "181", "-1"] {
            XCTAssertNil(ComponentMeshSmoothingInput.value(text))
            value.componentMeshSmoothingAction(text, target: target)()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(value.canUndo)
        }
        value.componentMeshSmoothingAction("180", target: target)()
        try await settle(value)
        XCTAssertTrue(
            value.snapshot?.selectedComponentRows.allSatisfy { $0.component.smoothCutoffDegrees == 180 } == true)
        XCTAssertEqual(
            EditorStore.message(ComponentMeshSelectionError.staleTarget),
            "The component settings selection changed. Choose the edit again.")
    }
    func testMixedAndUnsupportedControlsRenderBothAppearancesAndSingleSelectionHasNoBatchEditor() async throws {
        let value = store()
        defer { value.stop() }
        let original = try source()
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(["a", "b"])
        try await settle(value)
        XCTAssertTrue(ComponentMeshSelectionPresentation(snapshot: try XCTUnwrap(value.snapshot)).isAvailable)
        for kind in ["mixed", "unsupported", "uniform"] {
            if kind == "unsupported" {
                let xml = String(decoding: original.modelXML, as: UTF8.self).replacingOccurrences(
                    of: "inverse='true' smoothCutoffDegrees='090.00'",
                    with: "combineMode='OtherFuture' smoothCutoffDegrees='otherfuture'")
                await value.load(data: try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded())
                try await settle(value)
                value.selectComponents(["a", "b"])
                try await settle(value)
                XCTAssertEqual(
                    ComponentMeshSelectionPresentation(snapshot: try XCTUnwrap(value.snapshot)).combineMode,
                    .unsupported)
            }
            if kind == "uniform" {
                let xml = String(decoding: original.modelXML, as: UTF8.self)
                    .replacingOccurrences(
                        of: "inverse='true' smoothCutoffDegrees='090.00'",
                        with: "combineMode='Normal' smoothCutoffDegrees='90'"
                    )
                    .replacingOccurrences(
                        of: "combineMode='Future' smoothCutoffDegrees='future'",
                        with: "combineMode='Normal' smoothCutoffDegrees='90'")
                await value.load(data: try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded())
                try await settle(value)
                value.selectComponents(["a", "b"])
                try await settle(value)
            }
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    ComponentMeshSelectionControls(store: value), width: 320, scheme: scheme)
                XCTAssertGreaterThan(data.count, 1000)
                if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                    try data.write(
                        to: URL(fileURLWithPath: output).appendingPathComponent(
                            "mesh-settings-\(kind)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        value.selectComponents(["a"])
        try await settle(value)
        let single = try XCTUnwrap(value.snapshot)
        XCTAssertFalse(ComponentMeshSelectionPresentation(snapshot: single).isAvailable)
        XCTAssertFalse(value.canEditComponentMeshSettings(.init(snapshot: single)))
        XCTAssertFalse(value.canUndo)
    }
}
