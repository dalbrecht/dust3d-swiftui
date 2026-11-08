import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EquipmentSafeRenameTests: XCTestCase {
    @MainActor func testCopiedCapsuleRenameKeepsExactSuffixThroughReopenAndUndo() async throws {
        let source = try document()
        let component = try XCTUnwrap(try source.components().first)
        XCTAssertEqual(component.equipmentRenameBaseName, "Capsule @legacy")
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectComponent(component.id)
        let target = try XCTUnwrap(selected.equipmentSlotTarget)
        let unchanged = try await session.renameEquipmentComponentBase("Capsule @legacy", target: target)
        XCTAssertEqual(unchanged.document.encoded(), source.encoded())
        XCTAssertFalse(unchanged.canUndo)
        let renamed = try await session.renameEquipmentComponentBase("Body", target: target)
        let reopened = try Dust3DDocument(data: renamed.document.encoded())
        let updated = try XCTUnwrap(try reopened.components().first)
        XCTAssertEqual(updated.name, "Body @ armor/2  ")
        XCTAssertEqual(updated.equipmentSlot, " armor/2  ")
        XCTAssertEqual(updated.id, component.id)
        XCTAssertEqual(renamed.selectedComponentIDs, [component.id])
        XCTAssertEqual(renamed.previewIdentity, selected.previewIdentity)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    @MainActor func testCapturedRenameRejectsChangedSlotSelectionAndSource() async throws {
        let source = try document()
        let id = try XCTUnwrap(try source.components().first).id
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectComponent(id)
        let oldSlot = try XCTUnwrap(selected.equipmentSlotTarget)
        let slotChanged = try await session.setComponentEquipmentSlot("armor/9", target: oldSlot)
        try await assertStale(oldSlot, session: session)
        let oldSelection = try XCTUnwrap(slotChanged.equipmentSlotTarget)
        _ = try await session.selectComponent(nil)
        let reselected = try await session.selectComponent(id)
        try await assertStale(oldSelection, session: session)
        let oldSource = try XCTUnwrap(reselected.equipmentSlotTarget)
        _ = try await session.open(data: slotChanged.document.encoded())
        let current = try await session.selectComponent(id)
        try await assertStale(oldSource, session: session)
        let retained = try await session.selectComponent(id)
        XCTAssertEqual(retained.document.encoded(), current.document.encoded())
        XCTAssertFalse(retained.canUndo)
    }

    func testUnrecognizedSuffixDoesNotEnterBaseRenameAndRawRenameRemainsAvailable() throws {
        let source = try document()
        let id = try XCTUnwrap(try source.components().first).id
        let malformed = try source.applying(.setComponentName(id: id, name: "Capsule @"))
        XCTAssertNil(try malformed.components().first?.equipmentRenameBaseName)
        XCTAssertThrowsError(
            try malformed.applying(.setComponentBaseNamePreservingEquipmentSlot(id: id, name: "Body")))
        let plain = try malformed.applying(.setComponentName(id: id, name: "Body"))
        XCTAssertEqual(try plain.components().first?.name, "Body")
        XCTAssertNil(try plain.components().first?.equipmentSlot)
    }

    @MainActor private func assertStale(_ target: ComponentEquipmentSlotTarget, session: EditorSession) async throws {
        do {
            _ = try await session.renameEquipmentComponentBase("Stale", target: target)
            XCTFail("A retained equipment name edit must not retarget")
        } catch {
        }
    }

    private func document() throws -> Dust3DDocument {
        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let capsule = try Dust3DDocument(data: Data(contentsOf: fixture))
        let xml = String(decoding: capsule.modelXML, as: UTF8.self)
            .replacingOccurrences(of: "name=\"Capsule\"", with: "name=\"Capsule @legacy @ armor/2  \"")
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }
}
