import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PartCutFaceSessionTests: XCTestCase {
    func testCyclicProfileBatchLeavesHistorySelectionAndLocksUntouched() async throws {
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "node", partID: part, componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1)
        )
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectPart(part)
        _ = try await session.setLock(.radius, isLocked: true)
        do {
            _ = try await session.apply([
                .setPartCutRotation(id: part, rotation: 0.005), .setPartCutFace(id: part, selection: .linkedPart(part)),
            ])
            XCTFail("A profile cycle must reject the whole batch")
        } catch { XCTAssertEqual(error as? DocumentError, .cyclicProfile) }
        let unchanged = try await session.undo()
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertEqual(unchanged.selectedPartID, part)
        XCTAssertTrue(unchanged.locks.contains(.radius))
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertFalse(unchanged.canRedo)
        let changed = try await session.apply([
            .setPartCutFace(id: part, selection: .preset(.triangle)), .setPartCutRotation(id: part, rotation: 0.005),
        ])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
    }
}
