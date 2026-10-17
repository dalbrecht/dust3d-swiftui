import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PartDeformationSessionTests: XCTestCase {
    func testInvalidBatchLeavesHistorySelectionAndLocksUntouched() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectPart("part")
        _ = try await session.setLock(.radius, isLocked: true)
        do {
            _ = try await session.apply([
                .setPartDeformationScale(id: "part", property: .width, value: 0.995),
                .setPartDeformationUnified(id: "part", value: true),
                .setPartDeformationScale(id: "part", property: .thickness, value: .nan),
            ])
            XCTFail("An invalid scale must reject the whole batch")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidPartDeformation) }
        let unchanged = try await session.undo()
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertEqual(unchanged.selectedPartID, "part")
        XCTAssertTrue(unchanged.locks.contains(.radius))
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertFalse(unchanged.canRedo)
        let changed = try await session.apply([
            .setPartDeformationScale(id: "part", property: .width, value: 0.995),
            .setPartDeformationUnified(id: "part", value: true),
        ])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
    }
}
