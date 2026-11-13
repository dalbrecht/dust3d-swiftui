import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct EquipmentSlotNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
final class ComponentEquipmentSlotStoreTests: XCTestCase {
    func testStaleSelectionCannotAssignSlotAndCurrentAssignmentUndoesExactly() async throws {
        let xml = """
            <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='0.1'/></nodes>
            <parts><part id='p'/><part id='q'/></parts><components>
            <component id='vest' name='Vest @armor/1' linkDataType='partId' linkData='p'/>
            <component id='boot' name='Boot' linkDataType='partId' linkData='q'/></components></canvas>
            """
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let stub = EquipmentSlotNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)

        store.selectComponents(["vest"])
        try await settle(store)
        let first = try XCTUnwrap(store.snapshot)
        let stale = try XCTUnwrap(first.equipmentSlotTarget)
        store.selectComponents(["boot"])
        try await settle(store)
        store.selectComponents(["vest"])
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        XCTAssertNotEqual(before.selectionRevision, first.selectionRevision)

        store.setComponentEquipmentSlot("armor/2", target: stale)
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.snapshot?.selectedComponent?.name, "Vest @armor/1")

        store.setComponentEquipmentSlot("armor/2", target: try XCTUnwrap(before.equipmentSlotTarget))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.name, "Vest @armor/2")
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, before.selectedComponentIDs)
        XCTAssertEqual(store.snapshot?.previewIdentity, before.previewIdentity)
        XCTAssertTrue(store.canUndo)

        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(store.snapshot?.previewIdentity, before.previewIdentity)
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(store.canRedo)
    }

    func testGraphSlotStoreEditsWithoutLosingPicksAndRejectsFailedSource() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                <parts><part id='p'/></parts><components>
                <component id='vest' name='Vest @armor/1' linkDataType='partId' linkData='p'/>
                </components></canvas>
                """.utf8))
        let stub = EquipmentSlotNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.select("a")
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        let target = try XCTUnwrap(GraphModelPartTarget(snapshot: before).equipmentSlotTarget)
        store.setComponentEquipmentSlot("armor/2", target: target)
        try await settle(store)
        let changed = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(changed.selectedIDs, ["a"])
        XCTAssertEqual(changed.componentTree.rows.first?.component.equipmentSlot, "armor/2")
        XCTAssertEqual(changed.previewIdentity, before.previewIdentity)

        let retained = try XCTUnwrap(GraphModelPartTarget(snapshot: changed).equipmentSlotTarget)
        await store.load(data: Data("bad archive".utf8))
        let error = try XCTUnwrap(store.errorMessage)
        store.setComponentEquipmentSlot("", target: retained)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.errorMessage, error)
        XCTAssertEqual(store.snapshot?.document.encoded(), changed.document.encoded())
    }

    func testInspectorNameEditCannotRetargetAfterIndependentSlotEdit() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><parts><part id='p'/></parts><components>
                <component id='vest' name='Vest @armor/1' linkDataType='partId' linkData='p'/>
                </components></canvas>
                """.utf8))
        let stub = EquipmentSlotNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectComponents(["vest"])
        try await settle(store)
        let first = try XCTUnwrap(store.snapshot)
        let equipment = try XCTUnwrap(first.equipmentSlotTarget)
        let old = try XCTUnwrap(
            store.inspectedComponentNameAction(try XCTUnwrap(first.selectedComponent), equipment: equipment))
        store.setComponentEquipmentSlot("armor/2", target: equipment)
        try await settle(store)
        old("Wrong")
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedComponent?.name, "Vest @armor/2")

        let current = try XCTUnwrap(store.snapshot)
        let rename = try XCTUnwrap(
            store.inspectedComponentNameAction(
                try XCTUnwrap(current.selectedComponent), equipment: try XCTUnwrap(current.equipmentSlotTarget)))
        rename("Body")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedComponent?.name, "Body @armor/2")
        XCTAssertEqual(store.snapshot?.previewIdentity, first.previewIdentity)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Equipment slot store did not settle")
    }
}
