import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class ComponentEquipmentSlotSessionTests: XCTestCase {
    func testOnlyOneLinkedModelComponentProducesAnEquipmentTarget() async throws {
        let session = EditorSession()
        let opened = try await session.open(data: fixture().encoded())
        XCTAssertNil(opened.equipmentSlotTarget)
        for ids: Set<String> in [["model", "second"], ["profile"], ["group"], ["missing-owner"]] {
            let snapshot = try await session.selectComponents(ids)
            XCTAssertNil(snapshot.equipmentSlotTarget, "Unexpected equipment target for \(ids)")
        }
        let selected = try await session.selectComponents(["model"])
        XCTAssertNotNil(selected.equipmentSlotTarget)
    }

    func testEquipmentSlotEditIsOneUndoAndPreservesPreviewIdentityAndSelection() async throws {
        let original = try fixture()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.selectComponents(["model"])
        let target = try XCTUnwrap(before.equipmentSlotTarget)
        let edited = try await session.setComponentEquipmentSlot("  armor/2  ", target: target)
        XCTAssertEqual(edited.selectedComponent?.name, "Vest @armor/2")
        XCTAssertEqual(edited.selectedComponentIDs, before.selectedComponentIDs)
        XCTAssertEqual(edited.selectionRevision, before.selectionRevision)
        XCTAssertEqual(edited.previewIdentity, before.previewIdentity)
        XCTAssertTrue(edited.canUndo)
        XCTAssertFalse(edited.canRedo)

        let noOpTarget = try XCTUnwrap(edited.equipmentSlotTarget)
        let noOp = try await session.setComponentEquipmentSlot("armor/2", target: noOpTarget)
        XCTAssertEqual(noOp.document.encoded(), edited.document.encoded())
        XCTAssertEqual(noOp.documentRevision, edited.documentRevision)
        XCTAssertEqual(noOp.previewIdentity, edited.previewIdentity)

        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertEqual(undone.previewIdentity, before.previewIdentity)
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), edited.document.encoded())
        XCTAssertEqual(redone.previewIdentity, edited.previewIdentity)
        XCTAssertEqual(redone.selectedComponentIDs, before.selectedComponentIDs)
    }

    func testCapturedTargetRejectsSelectionABAAndLaterDocumentRevision() async throws {
        let original = try fixture()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["model"])
        let staleSelection = try XCTUnwrap(selected.equipmentSlotTarget)
        _ = try await session.selectComponents(["second"])
        let returned = try await session.selectComponents(["model"])
        XCTAssertNotEqual(returned.selectionRevision, selected.selectionRevision)
        do {
            _ = try await session.setComponentEquipmentSlot("armor/2", target: staleSelection)
            XCTFail("A captured target must reject a selection ABA")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        let afterSelectionRejection = try await session.selectComponents(["model"])
        XCTAssertEqual(afterSelectionRejection.document.encoded(), original.encoded())
        XCTAssertFalse(afterSelectionRejection.canUndo)

        let staleDocument = try XCTUnwrap(afterSelectionRejection.equipmentSlotTarget)
        let changed = try await session.apply([.setComponentName(id: "second", name: "Renamed")])
        XCTAssertGreaterThan(changed.documentRevision, afterSelectionRejection.documentRevision)
        do {
            _ = try await session.setComponentEquipmentSlot("armor/2", target: staleDocument)
            XCTFail("A captured target must reject a newer document revision")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        let afterDocumentRejection = try await session.selectComponents(["model"])
        XCTAssertEqual(afterDocumentRejection.document.encoded(), changed.document.encoded())
        XCTAssertEqual(afterDocumentRejection.documentRevision, changed.documentRevision)
    }

    func testGraphEquipmentTargetRequiresExactlyOneLinkedModelComponent() throws {
        var state = try EditorState(document: fixture())
        try state.selectGraph(nodes: ["a"], edges: ["ab"])
        XCTAssertEqual(GraphModelPartTarget(snapshot: state.snapshot).equipmentSlotTarget?.componentID, "model")
        XCTAssertNil(state.snapshot.equipmentSlotTarget)
        try state.selectGraph(nodes: ["c"], edges: ["ab"])
        XCTAssertNil(GraphModelPartTarget(snapshot: state.snapshot).equipmentSlotTarget)
        try state.select("d")
        XCTAssertNil(GraphModelPartTarget(snapshot: state.snapshot).equipmentSlotTarget)
        try state.selectComponent("model")
        XCTAssertNil(GraphModelPartTarget(snapshot: state.snapshot).equipmentSlotTarget)
        var duplicate = try EditorState(document: fixture(duplicateOwner: true))
        try duplicate.selectEdges(["ab"])
        XCTAssertNil(GraphModelPartTarget(snapshot: duplicate.snapshot).equipmentSlotTarget)
    }

    func testGraphEquipmentSlotTrimsClearsAndUndoesExactlyWithoutPreviewChange() async throws {
        let original = try fixture()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        let target = try XCTUnwrap(GraphModelPartTarget(snapshot: before).equipmentSlotTarget)
        let edited = try await session.setComponentEquipmentSlot("  armor/2  ", target: target)
        XCTAssertEqual(edited.componentTree.rows.first { $0.id == "model" }?.component.name, "Vest @armor/2")
        XCTAssertEqual(edited.selectedIDs, ["a"])
        XCTAssertEqual(edited.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(edited.previewIdentity, before.previewIdentity)
        let current = try XCTUnwrap(GraphModelPartTarget(snapshot: edited).equipmentSlotTarget)
        let noOp = try await session.setComponentEquipmentSlot("armor/2", target: current)
        XCTAssertEqual(noOp.document.encoded(), edited.document.encoded())
        XCTAssertEqual(noOp.documentRevision, edited.documentRevision)
        let cleared = try await session.setComponentEquipmentSlot("  ", target: current)
        XCTAssertEqual(cleared.componentTree.rows.first { $0.id == "model" }?.component.name, "Vest")
        let model = try XMLDocument(data: cleared.document.modelXML)
        let row = try XCTUnwrap(try model.nodes(forXPath: "//component[@id='model']").first as? XMLElement)
        XCTAssertEqual(row.attribute(forName: "future")?.stringValue, "retain")
        let undoClear = try await session.undo()
        XCTAssertEqual(undoClear.document.encoded(), edited.document.encoded())
        let undoEdit = try await session.undo()
        XCTAssertEqual(undoEdit.document.encoded(), original.encoded())
        XCTAssertFalse(undoEdit.canUndo)
    }

    func testGraphEquipmentTargetRejectsSelectionABAAndFailedSource() async throws {
        let original = try fixture()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let initial = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        let retired = try XCTUnwrap(GraphModelPartTarget(snapshot: initial).equipmentSlotTarget)
        _ = try await session.select("c")
        let restored = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        await assertGraphSlotRejected(session, target: retired)
        let current = try XCTUnwrap(GraphModelPartTarget(snapshot: restored).equipmentSlotTarget)
        do {
            _ = try await session.open(data: Data("bad archive".utf8))
            XCTFail("Invalid replacement opened")
        } catch {}
        await assertGraphSlotRejected(session, target: current)
        let retained = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        XCTAssertEqual(retained.document.encoded(), original.encoded())
        XCTAssertFalse(retained.canUndo)
    }

    private func assertGraphSlotRejected(_ session: EditorSession, target: ComponentEquipmentSlotTarget) async {
        do {
            _ = try await session.setComponentEquipmentSlot("armor/2", target: target)
            XCTFail("Retired graph slot target accepted an edit")
        } catch {
            XCTAssertEqual(error as? ComponentEquipmentSlotError, .staleTarget)
        }
    }

    private func fixture(duplicateOwner: Bool = false) throws -> Dust3DDocument {
        let xml = """
            <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='0.1'/>
            <node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
            <node id='c' partId='q' x='2' y='0' z='0' radius='.1'/>
            <node id='d' partId='r' x='3' y='0' z='0' radius='.1'/></nodes>
            <edges><edge id='ab' from='a' to='b' partId='p'/></edges>
            <parts><part id='p'/><part id='q' target='Model'/><part id='r' target='CutFace'/></parts>
            <components><component id='model' name='Vest @armor/1' future='retain' linkDataType='partId' linkData='p'/>
            <component id='second' name='Boot' linkDataType='partId' linkData='q'/>
            <component id='profile' linkDataType='partId' linkData='r'/><component id='group'/>
            <component id='missing-owner' linkDataType='partId' linkData='missing'/>
            \(duplicateOwner ? "<component id='duplicate' linkDataType='partId' linkData='p'/>" : "")
            </components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }
}
