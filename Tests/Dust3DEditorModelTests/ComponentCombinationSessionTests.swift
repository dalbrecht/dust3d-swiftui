import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ComponentCombinationSessionTests: XCTestCase {
    func testCombinationBatchIsAtomicAndKeepsSelectionAndEditingLocks() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectComponents(["component"])
        _ = try await session.setLock(.x, isLocked: true)
        let changed = try await session.apply([.setComponentCombineMode(id: "component", mode: .uncombined)])
        XCTAssertEqual(changed.selectedComponentID, "component")
        XCTAssertTrue(changed.locks.contains(.x))
        XCTAssertEqual(changed.selectedComponent?.combineMode, .uncombined)
        do {
            _ = try await session.apply([
                .setComponentCombineMode(id: "component", mode: .inversion),
                .setComponentCombineMode(id: "missing", mode: .normal),
            ])
            XCTFail("A failed combination batch must publish no partial changes")
        } catch {
            XCTAssertEqual(error as? DocumentError, .missingComponent("missing"))
        }
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
        XCTAssertEqual(redone.selectedComponentID, "component")
    }
}
