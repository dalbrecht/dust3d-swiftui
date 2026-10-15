import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PartSelectionTests: XCTestCase {
    private func separateParts() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "cp", position: .init(x: 0, y: 0, z: 0), radius: 0.1)
        ).applying(.addNode(id: "b", partID: "q", componentID: "cq", position: .init(x: 1, y: 0, z: 0), radius: 0.1))
    }
    func testPartSelectionIsExclusiveTransientAndAtomic() throws {
        let original = try separateParts().applying(
            .addNode(id: "c", partID: "p", componentID: nil, position: .init(x: 0, y: 1, z: 0), radius: 0.1)
        ).applying(.addEdge(id: "e", from: "a", to: "c"))
        var state = try EditorState(document: original)
        XCTAssertNil(state.snapshot.selectedPart)
        try state.select("a")
        try state.selectPart("p")
        XCTAssertEqual(state.snapshot.selectedPart?.id, "p")
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertNil(state.snapshot.selectedEdgeID)
        XCTAssertFalse(state.snapshot.canAddNode)
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertThrowsError(try state.selectPart("missing"))
        XCTAssertEqual(state.snapshot.selectedPartID, "p")
        try state.selectEdge("e")
        XCTAssertNil(state.snapshot.selectedPartID)
        try state.selectPart("p")
        state.selectAll()
        XCTAssertNil(state.snapshot.selectedPartID)
        try state.selectPart("p")
        try state.select(nil)
        XCTAssertNil(state.snapshot.selectedPartID)
        try state.selectPart("p")
        try state.selectPart(nil)
        XCTAssertNil(state.snapshot.selectedPartID)
    }
    func testDisabledPartsHideEditingButVisibilityDoesNotSuppressGeneration() throws {
        var state = try EditorState(document: separateParts())
        XCTAssertTrue(state.snapshot.hasEnabledGeometry)
        try state.apply([
            .setPartState(id: "p", property: .visible, value: false),
            .setPartState(id: "q", property: .visible, value: false),
        ])
        XCTAssertTrue(state.snapshot.hasEnabledGeometry)
        XCTAssertTrue(state.snapshot.nodes.allSatisfy { !$0.isVisible })
        try state.apply([
            .setPartState(id: "p", property: .disabled, value: true),
            .setPartState(id: "q", property: .disabled, value: true),
        ])
        XCTAssertFalse(state.snapshot.hasEnabledGeometry)
        try state.undo()
        XCTAssertTrue(state.snapshot.hasEnabledGeometry)
    }

    func testDisabledNodeEditingRejectsUntilExplicitPartRestoration() throws {
        var state = try EditorState(document: separateParts())
        try state.apply([.setPartState(id: "p", property: .disabled, value: true)])
        XCTAssertThrowsError(try state.edit(id: "a", position: .init(x: 0.2, y: 0, z: 0), radius: 0.1)) {
            XCTAssertEqual($0 as? EditorError, .readOnlyNode)
        }
        try state.apply([.setPartState(id: "p", property: .disabled, value: false)])
        try state.edit(id: "a", position: .init(x: 0.2, y: 0, z: 0), radius: 0.1)
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position.x, 0.2)
    }
    func testConsumedPartSelectionIsPrunedAndNotRestoredByUndo() throws {
        let original = try separateParts()
        var state = try EditorState(document: original)
        try state.selectPart("q")
        try state.apply([.joinNodes(id: "joined", from: "a", to: "b")])
        XCTAssertNil(state.snapshot.selectedPartID)
        XCTAssertEqual(state.snapshot.parts.count, 1)
        try state.undo()
        XCTAssertNil(state.snapshot.selectedPartID)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
    }
    func testActorPartSelectionAndUpdatesAreUndoable() async throws {
        let session = EditorSession()
        do {
            _ = try await session.selectPart("p")
            XCTFail("Open a document first")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        let original = try separateParts()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectPart("p")
        let updated = try await session.apply([
            .setPartName(id: "p", name: "Body"), .setPartState(id: "p", property: .locked, value: true),
        ])
        XCTAssertEqual(updated.selectedPart?.name, "Body")
        XCTAssertTrue(updated.selectedPart?.isLocked == true)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
        XCTAssertEqual(restored.selectedPartID, "p")
        XCTAssertFalse(restored.canUndo)
    }
}
