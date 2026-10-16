import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ComponentSessionTests: XCTestCase {
    func testComponentRenameUsesAtomicSessionHistoryAndPreservesSelectionAndLocks() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select("node")
        _ = try await session.setLock(.x, isLocked: true)
        let edited = try await session.apply([.setComponentName(id: "component", name: "Assembly")])
        XCTAssertEqual(try edited.document.components().first?.name, "Assembly")
        XCTAssertEqual(edited.selectedIDs, ["node"])
        XCTAssertTrue(edited.locks.contains(.x))
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), edited.document.encoded())
        do {
            _ = try await session.apply([
                .setComponentName(id: "component", name: "Partial"),
                .setComponentName(id: "missing", name: "Rejected"),
            ])
            XCTFail("The complete batch must reject")
        } catch {
            XCTAssertEqual(error as? DocumentError, .missingComponent("missing"))
        }
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
        let retry = try await session.redo()
        XCTAssertEqual(retry.document.encoded(), edited.document.encoded())
    }
}
