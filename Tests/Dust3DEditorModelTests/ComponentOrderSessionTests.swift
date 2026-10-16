import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentOrderSessionTests: XCTestCase {
    func testOrderAvailabilityAndSelectionFollowCommittedSiblingOrderAndHistory() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><components><component id='group'><component id='a'/><component id='b'><component id='only'/></component></component><component id='last'/></components></canvas>"
                    .utf8))
        let session = EditorSession()
        let opened = try await session.open(data: original.encoded())
        XCTAssertTrue(opened.availableComponentOrderMoves.isEmpty)
        XCTAssertTrue(opened.componentTree.orderMoves(for: "missing").isEmpty)
        XCTAssertTrue(opened.componentTree.orderMoves(for: "only").isEmpty)
        XCTAssertEqual(opened.componentTree.orderMoves(for: "group"), [.down, .last])
        XCTAssertEqual(opened.componentTree.orderMoves(for: "last"), [.up, .first])
        let selected = try await session.selectComponent("a")
        XCTAssertEqual(selected.availableComponentOrderMoves, [.down, .last])
        let moved = try await session.apply([.reorderComponent(id: "a", direction: .down)])
        XCTAssertEqual(moved.selectedComponentID, "a")
        XCTAssertEqual(moved.availableComponentOrderMoves, [.up, .first])
        XCTAssertEqual(moved.componentTree.rows.map(\.id), ["group", "b", "only", "a", "last"])
        let undone = try await session.undo()
        XCTAssertEqual(undone.availableComponentOrderMoves, [.down, .last])
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let noop = try await session.apply([.reorderComponent(id: "a", direction: .up)])
        XCTAssertTrue(noop.canRedo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), moved.document.encoded())
        do {
            _ = try await session.apply([
                .reorderComponent(id: "a", direction: .up), .reorderComponent(id: "missing", direction: .up),
            ])
            XCTFail("The complete batch must reject")
        } catch { XCTAssertEqual(error as? DocumentError, .missingComponent("missing")) }
        let afterFailure = try await session.undo()
        XCTAssertEqual(afterFailure.document.encoded(), original.encoded())
    }
}
