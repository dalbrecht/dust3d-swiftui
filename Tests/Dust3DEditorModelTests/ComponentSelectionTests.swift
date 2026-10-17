import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class ComponentSelectionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><components><component id='group'><component id='a'/><component id='b'><payload/></component></component><component id='empty'/><component id='opaque' linkDataType='future'><component id='nested'><payload/></component></component><component id='extension'><payload/></component></components></canvas>
                """.utf8))
    }

    func testComponentMultiSelectionIsAtomicExclusiveAndHistoryFree() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.selectComponents(["b", "a"])
        XCTAssertEqual(state.snapshot.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(state.snapshot.selectedComponentRows.map(\.id), ["a", "b"])
        XCTAssertNil(state.snapshot.selectedComponentID)
        XCTAssertNil(state.snapshot.selectedComponent)
        XCTAssertTrue(state.snapshot.availableComponentOrderMoves.isEmpty)
        XCTAssertTrue(state.snapshot.canGroupComponents)
        XCTAssertFalse(state.snapshot.canUngroupComponent)
        XCTAssertThrowsError(try state.selectComponents(["a", "missing"])) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
        }
        XCTAssertEqual(state.snapshot.selectedComponentIDs, ["a", "b"])
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.documentRevision, 0)
        try state.selectComponent("group")
        XCTAssertEqual(state.snapshot.selectedComponentIDs, ["group"])
        XCTAssertTrue(state.snapshot.canUngroupComponent)
        try state.selectComponents([])
        XCTAssertFalse(state.snapshot.canGroupComponents)
        XCTAssertFalse(state.snapshot.canUngroupComponent)
        try state.selectComponents(["group", "a"])
        XCTAssertFalse(state.snapshot.canGroupComponents)
        try state.selectComponent("b")
        XCTAssertTrue(state.snapshot.canUngroupComponent)
        try state.selectComponent("nested")
        XCTAssertFalse(state.snapshot.canGroupComponents)
        XCTAssertFalse(state.snapshot.canUngroupComponent)
        try state.selectComponent("empty")
        XCTAssertTrue(state.snapshot.canGroupComponents)
        XCTAssertFalse(state.snapshot.canUngroupComponent)
        try state.selectComponent("opaque")
        XCTAssertFalse(state.snapshot.canUngroupComponent)
        try state.selectComponent("extension")
        XCTAssertTrue(state.snapshot.canUngroupComponent)
        try state.select(Set<String>())
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        try state.selectComponent("a")
        state.selectAll()
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        try state.selectComponent("a")
        try state.selectEdge(nil)
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        try state.selectComponent("a")
        try state.selectPart(nil)
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
    }

    func testSelectionPrunesDeletedGroupsWithoutRevivingThemOnUndo() async throws {
        let session = EditorSession()
        let original = try document()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectComponents(["group", "empty"])
        let ungrouped = try await session.apply([.ungroupComponent(id: "group")])
        XCTAssertEqual(ungrouped.selectedComponentIDs, ["empty"])
        XCTAssertEqual(ungrouped.selectedComponentID, "empty")
        let undone = try await session.undo()
        XCTAssertEqual(undone.selectedComponentIDs, ["empty"])
        XCTAssertEqual(undone.document.encoded(), original.encoded())
    }
}
