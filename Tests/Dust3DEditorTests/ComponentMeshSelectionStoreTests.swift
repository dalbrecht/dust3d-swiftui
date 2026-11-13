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
    func testInspectedCutFaceCannotApplyCombineMode() async throws {
        let source = try source()
        let store = store()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectComponent("a")
        try await settle(store)
        let target = CanvasAdjustmentTarget(snapshot: try XCTUnwrap(store.snapshot))
        store.setComponentCombineMode("a", mode: .normal, target: target)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }
    func testGraphSingletonCanEditWhileSidebarSingletonKeepsItsOwnRoute() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id="a" partId="p" x="0" y="0" z="0" radius=".1"/></nodes>
                <parts><part id="p"/></parts><components>
                <component id="owner" linkDataType="partId" linkData="p"/>
                </components></canvas>
                """.utf8))
        let store = store()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)

        store.selectComponent("owner")
        try await settle(store)
        let sidebarTarget = ComponentMeshSelectionTarget(snapshot: try XCTUnwrap(store.snapshot))
        XCTAssertEqual(sidebarTarget.count, 1)
        XCTAssertFalse(store.canEditComponentMeshSettings(sidebarTarget))

        store.selectGraph(nodes: ["a"], edges: [])
        try await settle(store)
        let graphTarget = ComponentMeshSelectionTarget(graphSelection: try XCTUnwrap(store.snapshot))
        XCTAssertEqual(graphTarget.count, 1)
        XCTAssertTrue(store.canEditComponentMeshSettings(graphTarget))
        store.componentMeshAction(.combineMode(.inversion), target: graphTarget)()
        try await settle(store)
        let changed = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(changed.componentTree.rows.first?.component.combineMode, .inversion)
        XCTAssertEqual(changed.selectedIDs, ["a"])
        XCTAssertTrue(store.canUndo)
    }

    func testGraphCrossSectionStoreRejectsRetainedTargetsAndFailedLoadDrafts() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes>
                <parts><part id='p'/></parts><components><component id='owner' linkDataType='partId' linkData='p'/>
                </components></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: source.encoded())
        value.select("a")
        try await settle(value)
        let target = GraphPartCrossSectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        value.setGraphPartCutRotation("-0.25", target: target)
        try await settle(value)
        let changed = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(changed.parts.first?.cutRotation, -0.25)
        XCTAssertEqual(changed.selectedIDs, ["a"])
        value.editGraphPartCrossSection(.profile(.preset(.triangle)), target: target)
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())
        let retained = GraphPartCrossSectionTarget(snapshot: changed)
        await value.load(data: Data("invalid archive".utf8))
        let loadError = try XCTUnwrap(value.errorMessage)
        value.setGraphPartCutRotation("invalid", target: retained)
        XCTAssertEqual(value.errorMessage, loadError)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())
    }

    func testGraphDeformationStoreGuardsRetainedDraftsBeforeParsing() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes>
                <parts><part id='p'/></parts><components><component id='owner' linkDataType='partId' linkData='p'/>
                </components></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: source.encoded())
        value.select("a")
        try await settle(value)
        let target = GraphPartCrossSectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        value.setGraphPartDeformationScale(.width, value: "1.25", target: target)
        try await settle(value)
        let changed = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(changed.parts.first?.deformationScale(.width), 1.25)
        XCTAssertEqual(changed.selectedIDs, ["a"])
        value.setGraphPartDeformationScale(.width, value: "invalid", target: target)
        XCTAssertNil(value.errorMessage)
        let retained = GraphPartCrossSectionTarget(snapshot: changed)
        await value.load(data: Data("invalid archive".utf8))
        let loadError = try XCTUnwrap(value.errorMessage)
        value.setGraphPartDeformationScale(.width, value: "invalid", target: retained)
        value.editGraphPartCrossSection(.deformationUnified(true), target: retained)
        XCTAssertEqual(value.errorMessage, loadError)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())
    }

    func testGraphOwnerMirrorReplacesUnsupportedValueAndPreservesExactUndo() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                <parts><part id='p' xMirrored='future'/></parts><components>
                <component id='owner' linkDataType='partId' linkData='p'/>
                </components></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        value.select("a")
        try await settle(value)
        let initial = PartMirrorTarget(graphTarget: GraphModelPartTarget(snapshot: try XCTUnwrap(value.snapshot)))
        XCTAssertTrue(value.canEditPartMirror(initial))
        value.partMirrorAction(false, target: initial)()
        try await settle(value)
        let changed = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(changed.parts.first?.xMirrored, false)
        XCTAssertEqual(changed.selectedIDs, ["a"])
        XCTAssertNil(changed.origin)
        value.partMirrorAction(true, target: initial)()
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }

    func testGraphOwnerMaterialApplyAndResetRejectRetiredAndFailedSourceTargets() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                <parts><part id='p' emissive='.75'/></parts><components>
                <component id='owner' linkDataType='partId' linkData='p'/>
                </components></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: source.encoded())
        value.select("a")
        try await settle(value)
        let initial = GraphModelPartTarget(snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertTrue(value.canEditGraphPartMaterial(initial))
        value.setGraphPartMaterial(.emissive, value: "2", target: initial)
        try await settle(value)
        let changed = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(changed.parts.first?.materialValue(.emissive), 2)
        value.resetGraphPartMaterial(.emissive, target: initial)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())

        value.resetGraphPartMaterial(.emissive, target: GraphModelPartTarget(snapshot: changed))
        try await settle(value)
        let reset = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(reset.parts.first?.materialValue(.emissive), 0)
        XCTAssertEqual(reset.selectedIDs, ["a"])
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())

        let retained = GraphModelPartTarget(snapshot: try XCTUnwrap(value.snapshot))
        await value.load(data: Data("bad archive".utf8))
        let loadError = try XCTUnwrap(value.errorMessage)
        XCTAssertFalse(value.canEditGraphPartMaterial(retained))
        value.setGraphPartMaterial(.emissive, value: "invalid", target: retained)
        value.resetGraphPartMaterial(.emissive, target: retained)
        XCTAssertEqual(value.errorMessage, loadError)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())
    }

    func testGraphOwnerRoleRoutesCapturedPickerAndRejectsFailedReload() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                <parts><part id='p' target='CutFace'/></parts><components>
                <component id='owner' linkDataType='partId' linkData='p'/>
                </components></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: source.encoded())
        value.select("a")
        try await settle(value)
        let initial = GraphPartRoleTarget(snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertTrue(value.canEditGraphPartRole(initial))
        value.setGraphPartRole(.model, target: initial)
        try await settle(value)
        let changed = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(changed.parts.first?.target, .model)
        XCTAssertEqual(changed.selectedIDs, ["a"])
        value.setGraphPartRole(.stitchingLine, target: initial)
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())

        let retained = GraphPartRoleTarget(snapshot: changed)
        await value.load(data: Data("bad archive".utf8))
        let loadError = try XCTUnwrap(value.errorMessage)
        XCTAssertFalse(value.canEditGraphPartRole(retained))
        value.setGraphPartRole(.cutFace, target: retained)
        XCTAssertEqual(value.errorMessage, loadError)
        XCTAssertEqual(value.snapshot?.document.encoded(), changed.document.encoded())
    }

    func testGraphOwnerColorSingletonAndFailedSourcePreserveExactHistory() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                <parts><part id='p'/></parts><components>
                <component id='owner' linkDataType='partId' linkData='p' color='future'/>
                </components></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: source.encoded())
        value.selectComponent("owner")
        try await settle(value)
        value.setSelectedComponentColors(
            ComponentMeshSelectionTarget(snapshot: try XCTUnwrap(value.snapshot)), value: "#80102030")
        XCTAssertFalse(value.isWorking, "Sidebar singleton continues to use its own inspector")
        value.select("a")
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        let target = ComponentMeshSelectionTarget(graphSelection: before)
        var writes = 0
        value.onDocumentChanged = { _ in writes += 1 }
        value.setSelectedComponentColors(target, value: "#80102030")
        try await settle(value)
        let colored = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(
            colored.componentTree.rows.first?.component.color, .value(.init(red: 16, green: 32, blue: 48, alpha: 128)))
        XCTAssertEqual(colored.selectedIDs, ["a"])
        XCTAssertTrue(colored.selectedComponentIDs.isEmpty)
        XCTAssertEqual(writes, 1)
        value.setSelectedComponentColors(ComponentMeshSelectionTarget(graphSelection: colored), value: "#80102030")
        try await settle(value)
        XCTAssertEqual(writes, 1)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), source.encoded())
        value.redo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), colored.document.encoded())

        let retained = ComponentMeshSelectionTarget(graphSelection: try XCTUnwrap(value.snapshot))
        await value.load(data: Data("invalid archive".utf8), fileIdentity: UUID())
        let loadError = try XCTUnwrap(value.errorMessage)
        value.setSelectedComponentColors(retained, value: "invalid")
        value.setSelectedComponentColors(retained, value: nil)
        try await settle(value)
        XCTAssertEqual(value.errorMessage, loadError)
        XCTAssertEqual(value.snapshot?.document.encoded(), colored.document.encoded())
        XCTAssertEqual(writes, 3)
    }

    func testDanglingPartAliasCannotEnableOrPublishComponentStateActions() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='cafe&#769;'/></parts><components><component id='dangling' linkDataType='partId' linkData='caf&#233;'/></components></canvas>"
                    .utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponent("dangling")
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        let target = ComponentMeshSelectionTarget(snapshot: before)
        XCTAssertTrue(target.isCurrent(in: before))
        XCTAssertTrue(value.selectedParts(for: target).isEmpty)
        let message = value.errorMessage
        value.setSelectedComponentPartState(.locked, value: true, target: target)
        XCTAssertFalse(value.isWorking)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(value.snapshot?.previewIdentity, before.previewIdentity)
        XCTAssertEqual(value.errorMessage, message)
        XCTAssertFalse(value.canUndo)
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
    func testBatchComponentColorAppliesAndClearsWithOneUndoEach() async throws {
        let original = try source()
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        let selected: Set<String> = ["a", "b"]
        value.selectComponents(selected)
        try await settle(value)
        let color = try XCTUnwrap(DocumentColor(archiveValue: "#2255AA"))
        let target = ComponentMeshSelectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        value.setSelectedComponentColors(target, value: "#2255AA")
        try await settle(value)
        let colored = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(colored.selectedComponentIDs, selected)
        XCTAssertNotEqual(target, ComponentMeshSelectionTarget(snapshot: colored))
        XCTAssertEqual(colored.selectedComponentRows.count, 2)
        XCTAssertTrue(colored.selectedComponentRows.allSatisfy { $0.component.color == .value(color) })
        value.setSelectedComponentColors(target, value: nil)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), colored.document.encoded())
        value.setSelectedComponentColors(ComponentMeshSelectionTarget(snapshot: colored), value: nil)
        try await settle(value)
        XCTAssertTrue(value.snapshot?.selectedComponentRows.allSatisfy { $0.component.color == .unset } == true)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), colored.document.encoded())
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }

    func testBatchPartStateUsesDirectOwnersAndUpdatesPreviewOnlyWhenNeeded() async throws {
        let xml = """
            <canvas><nodes/><edges/><parts><part id='p'/><part id='q'/><part id='r'/></parts><components>
            <component id='a' linkDataType='partId' linkData='p'/>
            <component id='alias' linkDataType='partId' linkData='p'/>
            <component id='b' linkDataType='partId' linkData='q'/>
            <component id='g'><component id='c' linkDataType='partId' linkData='r'/></component>
            </components></canvas>
            """
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        let selection: Set<String> = ["a", "alias", "b", "g"]
        value.selectComponents(selection)
        try await settle(value)
        let initial = try XCTUnwrap(value.snapshot)
        let target = ComponentMeshSelectionTarget(snapshot: initial)
        XCTAssertEqual(value.selectedParts(for: target).map(\.id), ["p", "q"])

        value.setSelectedComponentPartState(.visible, value: true, target: target)
        XCTAssertFalse(value.isWorking)
        XCTAssertFalse(value.canUndo)
        value.setSelectedComponentPartState(.visible, value: false, target: target)
        try await settle(value)
        let hidden = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(hidden.selectedComponentIDs, selection)
        XCTAssertEqual(hidden.parts.map(\.isVisible), [false, false, true])
        XCTAssertEqual(hidden.previewIdentity, initial.previewIdentity)
        XCTAssertTrue(value.selectedParts(for: target).isEmpty)

        value.setSelectedComponentPartState(.disabled, value: true, target: target)
        XCTAssertFalse(value.isWorking)
        value.setSelectedComponentPartState(
            .disabled, value: true, target: ComponentMeshSelectionTarget(snapshot: hidden))
        try await settle(value)
        let disabled = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(disabled.parts.map(\.isDisabled), [true, true, false])
        XCTAssertNotEqual(disabled.previewIdentity.geometry, hidden.previewIdentity.geometry)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), hidden.document.encoded())
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
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
