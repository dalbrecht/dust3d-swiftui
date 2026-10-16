import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentStructureSessionTests: XCTestCase {
    func testSessionAllocatesFreshGroupIdentityAndStructuralHistoryIsAtomic() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><components><component id='a'/><component id='b'/><component id='c'/></components></canvas>"
                    .utf8))
        let first = EditorSession()
        let second = EditorSession()
        _ = try await first.open(data: original.encoded())
        _ = try await second.open(data: original.encoded())
        let grouped = try await first.groupComponents(["c", "a"])
        let id = try XCTUnwrap(grouped.selectedComponentID)
        XCTAssertNotNil(UUID(uuidString: String(id.dropFirst().dropLast())))
        XCTAssertEqual(grouped.selectedComponent?.childIDs, ["a", "c"])
        XCTAssertEqual(grouped.componentTree.rows.filter { $0.component.parentID == nil }.map(\.id), [id, "b"])
        let other = try await second.groupComponents(["a", "c"])
        XCTAssertNotEqual(other.selectedComponentID, id)
        let originalBytes = try await first.undo()
        XCTAssertEqual(originalBytes.document.encoded(), original.encoded())
        XCTAssertNil(originalBytes.selectedComponentID)
        let redone = try await first.redo()
        XCTAssertEqual(redone.document.encoded(), grouped.document.encoded())
        _ = try await first.selectComponent(id)
        do {
            _ = try await first.apply([
                .reparentComponent(id: "b", parentID: id), .reparentComponent(id: id, parentID: "b"),
            ])
            XCTFail("A cyclic batch must not publish its first move")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidComponentStructure) }
        let ungrouped = try await first.apply([.ungroupComponent(id: id)])
        XCTAssertEqual(ungrouped.componentTree.rows.map(\.id), ["a", "c", "b"])
        XCTAssertNil(ungrouped.selectedComponentID)
        let restored = try await first.undo()
        XCTAssertEqual(restored.document.encoded(), grouped.document.encoded())
        XCTAssertNil(restored.selectedComponentID)
        do {
            _ = try await first.groupComponents([])
            XCTFail("Empty grouping must reject")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidComponentStructure) }
        let undone = try await first.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
    }
}
