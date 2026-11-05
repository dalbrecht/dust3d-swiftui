import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class NodeReductionSessionTests: XCTestCase {
    private func chain() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ["a", "b", "c", "d"].enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: "p", componentID: index == 0 ? "component" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        for (id, from, to) in [("ab", "a", "b"), ("bc", "b", "c"), ("cd", "c", "d")] {
            document = try document.applying(.addEdge(id: id, from: from, to: to))
        }
        return document
    }

    func testFullBatchReductionSkipsEndpointAndPrunesOnlyRemovedSelectionsInOneUndoStep() async throws {
        let original = try chain()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select(Set(["a", "b", "c"]))
        let reduced = try await session.reduceSelectedNodes()
        XCTAssertEqual(Set(reduced.nodes.map(\.id)), ["a", "d"])
        XCTAssertEqual(reduced.edges.count, 1)
        XCTAssertEqual(reduced.selectedIDs, ["a"])
        XCTAssertEqual(reduced.selectedID, "a")
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertEqual(undone.selectedIDs, ["a"], "Undo does not revive removed transient selections")
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), reduced.document.encoded())
    }

    func testInvalidSelectedTopologyRejectsWholeBatchAndRetainsSelection() throws {
        let xml = """
            <canvas><nodes>
            <node id="a" partId="p" x="0" y="0" z="0" radius="0.1"/>
            <node id="b" partId="p" x="1" y="0" z="0" radius="0.1"/>
            <node id="c" partId="p" x="2" y="0" z="0" radius="0.1"/>
            </nodes><parts><part id="p"/><part id="q"/></parts><edges>
            <edge id="ab" partId="p" from="a" to="b"/>
            <edge id="bc" partId="q" from="b" to="c"/>
            </edges></canvas>
            """
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        var state = try EditorState(document: original)
        try state.select(Set(["a", "b"]))
        XCTAssertFalse(state.snapshot.canReduceSelectedNodes)
        XCTAssertThrowsError(try state.reduceSelectedNodes())
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b"])
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testOrderOnlyTransactionAndUndoRedoPreserveFutureReductionWithoutPreviewChanges() throws {
        let model = try XMLDocument(data: chain().modelXML)
        let edge = try XCTUnwrap(model.nodes(forXPath: "/canvas/edges/edge[@id='bc']").first as? XMLElement)
        let parent = try XCTUnwrap(edge.parent as? XMLElement)
        edge.detach()
        parent.addChild(edge)
        let original = try Dust3DDocument(snapshotXML: model.xmlData())
        var state = try EditorState(document: original)
        let preview = state.snapshot.previewIdentity
        try state.apply([.removeEdge(id: "bc"), .addEdge(id: "bc", from: "b", to: "c")])
        XCTAssertTrue(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertEqual(state.snapshot.previewIdentity, preview)
        XCTAssertEqual(
            try state.snapshot.document.applying(.reduceNodes(["c"])).editorContents().edges.map(\.id), ["ab", "cd"])
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertEqual(state.snapshot.previewIdentity, preview)
        XCTAssertEqual(
            try state.snapshot.document.applying(.reduceNodes(["c"])).editorContents().edges.map(\.id), ["ab", "bc"])
        try state.redo()
        XCTAssertEqual(state.snapshot.previewIdentity, preview)
        XCTAssertEqual(
            try state.snapshot.document.applying(.reduceNodes(["c"])).editorContents().edges.map(\.id), ["ab", "cd"])
    }

    func testEligibilityAndReadOnlyRejectionLeaveHistoryAndSelectionUntouched() throws {
        let original = try chain()
        var state = try EditorState(document: original)
        XCTAssertFalse(state.snapshot.canReduceSelectedNodes)
        try state.select(Set(["a", "d"]))
        XCTAssertFalse(state.snapshot.canReduceSelectedNodes)
        try state.reduceSelectedNodes()
        XCTAssertFalse(state.snapshot.canUndo)
        try state.select(Set(["b", "c"]))
        XCTAssertTrue(state.snapshot.canReduceSelectedNodes)
        let locked = try original.applying(.setPartState(id: "p", property: .locked, value: true))
        var readonly = try EditorState(document: locked)
        try readonly.select(Set(["b", "c"]))
        XCTAssertFalse(readonly.snapshot.canReduceSelectedNodes)
        XCTAssertThrowsError(try readonly.reduceSelectedNodes())
        XCTAssertEqual(readonly.snapshot.selectedIDs, ["b", "c"])
        XCTAssertEqual(readonly.snapshot.document.encoded(), locked.encoded())
        XCTAssertFalse(readonly.snapshot.canUndo)
    }
}
