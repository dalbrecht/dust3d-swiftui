import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentTreeTests: XCTestCase {
    private func document(
        _ components: String =
            "<component id='group'><component id='leaf' name='Body' linkDataType='partId' linkData='p'/><component id='nested'><component id='deep'/></component></component><component id='last' name='Root'/>"
    ) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='n' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='p'/></parts><components>\(components)</components></canvas>"
                    .utf8))
    }
    func testTreeRowsPreservePreorderDepthTitlesAndCollapsedSubtrees() throws {
        let tree = ComponentTree(document: try document())
        XCTAssertNil(tree.failureDescription)
        XCTAssertEqual(tree.rows.map(\.id), ["group", "leaf", "nested", "deep", "last"])
        XCTAssertEqual(tree.rows.map(\.depth), [0, 1, 1, 2, 0])
        XCTAssertEqual(tree.rows.map(\.title), ["Group 1", "Body", "Group 3", "Component 4", "Root"])
        XCTAssertEqual(tree.visibleRows(collapsing: ["group"]).map(\.id), ["group", "last"])
        XCTAssertEqual(
            tree.visibleRows(collapsing: ["nested", "missing"]).map(\.id), ["group", "leaf", "nested", "last"])
        XCTAssertEqual(tree.visibleRows(collapsing: ["leaf"]).map(\.id), tree.rows.map(\.id))
        XCTAssertTrue(ComponentTree(document: try Dust3DDocument(data: Dust3DDocument.emptyArchive())).rows.isEmpty)
    }
    func testUnsupportedHierarchySurfacesCauseWithoutPreventingGraphEditingOrSave() throws {
        let original = try document("<component id='same'/><component id='same'/>")
        var state = try EditorState(document: original)
        XCTAssertTrue(state.snapshot.componentTree.rows.isEmpty)
        XCTAssertTrue(state.snapshot.componentTree.failureDescription?.contains("invalidComponent") == true)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        try state.select("n")
        try state.moveSelection(by: .init(x: 1, y: 0, z: 0))
        XCTAssertEqual(state.snapshot.nodes.first?.value.position.x, 1)
        XCTAssertNotNil(state.snapshot.componentTree.failureDescription)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
    }
    func testComponentSelectionIsExclusiveTransientAndMissingSelectionIsAtomic() throws {
        var state = try EditorState(document: document())
        try state.select("n")
        try state.selectComponent("group")
        XCTAssertEqual(state.snapshot.selectedComponent?.id, "group")
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertNil(state.snapshot.selectedPartID)
        XCTAssertNil(state.snapshot.selectedEdgeID)
        XCTAssertFalse(state.snapshot.canAddNode)
        XCTAssertFalse(state.snapshot.canUndo)
        let baseline = state.snapshot.document.encoded()
        XCTAssertThrowsError(try state.selectComponent("missing"))
        XCTAssertEqual(state.snapshot.selectedComponentID, "group")
        try state.selectPart("p")
        XCTAssertNil(state.snapshot.selectedComponentID)
        try state.selectComponent("leaf")
        state.selectAll()
        XCTAssertNil(state.snapshot.selectedComponentID)
        try state.selectComponent("leaf")
        try state.selectEdge(nil)
        XCTAssertNil(state.snapshot.selectedComponentID)
        try state.selectComponent("leaf")
        try state.select(nil)
        XCTAssertNil(state.snapshot.selectedComponentID)
        try state.selectComponent("group")
        try state.selectComponent(nil)
        XCTAssertNil(state.snapshot.selectedComponentID)
        XCTAssertEqual(state.snapshot.document.encoded(), baseline)
    }
    func testRenameRetainsComponentSelectionAndDeletedComponentSelectionDoesNotReviveWithUndo() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "n", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        let other = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await other.open(data: original.encoded())
        _ = try await session.selectComponent("c")
        let renamed = try await session.apply([.setComponentName(id: "c", name: "Renamed")])
        XCTAssertEqual(renamed.selectedComponent?.name, "Renamed")
        let independent = try await other.selectPart("p")
        XCTAssertNil(independent.selectedComponentID)
        let deleted = try await session.apply([.removeNode(id: "n")])
        XCTAssertNil(deleted.selectedComponentID)
        let undone = try await session.undo()
        XCTAssertNil(undone.selectedComponentID)
        XCTAssertEqual(undone.componentTree.rows.first?.component.name, "Renamed")
        let reopened = try await session.open(data: original.encoded())
        XCTAssertNil(reopened.selectedComponentID)
    }
}
