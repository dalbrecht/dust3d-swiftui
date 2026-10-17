import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ComponentSmoothingSessionTests: XCTestCase {
    func testInvalidSmoothingBatchLeavesHistorySelectionAndLocksUntouched() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectComponent("component")
        _ = try await session.setLock(.radius, isLocked: true)
        do {
            _ = try await session.apply([
                .setComponentSmoothCutoffDegrees(id: "component", degrees: 90),
                .setComponentSmoothCutoffDegrees(id: "component", degrees: 181),
            ])
            XCTFail("A failed smoothing batch must publish no partial changes")
        } catch {
            XCTAssertEqual(error as? DocumentError, .invalidComponentSmoothing)
        }
        let unchanged = try await session.undo()
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertEqual(unchanged.selectedComponentID, "component")
        XCTAssertTrue(unchanged.locks.contains(.radius))
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertFalse(unchanged.canRedo)
        let changed = try await session.apply([.setComponentSmoothCutoffDegrees(id: "component", degrees: 90)])
        XCTAssertEqual(changed.selectedComponent?.smoothCutoffDegrees, 90)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
    }
}
