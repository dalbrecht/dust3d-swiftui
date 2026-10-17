import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ComponentWrappingSessionTests: XCTestCase {
    func testInvalidWrappingBatchPreservesHistorySelectionLocksAndRedo() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.2)
        ).applying(.groupComponents(ids: ["component"], groupID: "group"))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectComponent("group")
        _ = try await session.setLock(.radius, isLocked: true)
        let edited = try await session.apply([.setComponentWrapMode(id: "group", mode: .cloth)])
        _ = try await session.undo()
        do {
            _ = try await session.apply([
                .setComponentWrapMode(id: "group", mode: .skin), .setComponentWrapFaces(id: "group", faces: 63),
            ])
            XCTFail("Invalid wrapping batch must publish no partial edit")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidComponentWrapping) }
        let unchanged = try await session.undo()
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertEqual(unchanged.selectedComponentID, "group")
        XCTAssertTrue(unchanged.locks.contains(.radius))
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertTrue(unchanged.canRedo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), edited.document.encoded())
    }
}
