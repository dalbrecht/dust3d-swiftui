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

extension ComponentOrderSessionTests {
    func testBatchPlacementPreservesSelectionAndUsesOneUndoStep() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='a'/><component id='b'/><component id='c'/><component id='d'/></components></canvas>"
                    .utf8))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["b", "d"])
        let target = try XCTUnwrap(ComponentPlacementTarget(snapshot: selected))
        let moved = try await session.placeComponents(at: .before("a"), target: target)
        XCTAssertEqual(moved.componentTree.rows.map(\.id), ["b", "d", "a", "c"])
        XCTAssertEqual(moved.selectedComponentIDs, ["b", "d"])
        do {
            _ = try await session.placeComponents(at: .after("c"), target: target)
            XCTFail("A previous document revision must reject placement")
        } catch EditorError.staleComponentMove {}
        let current = try XCTUnwrap(ComponentPlacementTarget(snapshot: moved))
        _ = try await session.placeComponents(at: .before("a"), target: current)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), moved.document.encoded())
    }
}

extension ComponentOrderSessionTests {
    func testContextualPlacementMovesGrabbedRowWithoutChangingSelection() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='a'/><component id='b'/><component id='c'/></components></canvas>"
                    .utf8))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["a", "b"])
        XCTAssertNil(ComponentPlacementTarget(snapshot: selected, grabbedID: "missing"))
        let target = try XCTUnwrap(ComponentPlacementTarget(snapshot: selected, grabbedID: "c"))
        let moved = try await session.placeComponents(at: .before("a"), target: target)
        XCTAssertEqual(moved.componentTree.rows.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(moved.selectedComponentIDs, ["a", "b"])
        let group = try XCTUnwrap(ComponentPlacementTarget(snapshot: moved, grabbedID: "b"))
        let reordered = try await session.placeComponents(at: .before("c"), target: group)
        XCTAssertEqual(reordered.componentTree.rows.map(\.id), ["a", "b", "c"])
    }
}
