import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class GraphSelectionSubtractionTests: XCTestCase {
    private func document(nodeID: String = "a") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='\(nodeID)' partId='p' x='0' y='0' z='0' radius='0.1'/><node id='b' partId='p' x='1' y='0' z='0' radius='0.1'/><node id='c' partId='p' x='2' y='0' z='0' radius='0.1'/></nodes><edges><edge id='ab' partId='p' from='\(nodeID)' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p'/></parts><components><component id='group'><component id='leaf' linkData='p' linkDataType='partId'/></component></components></canvas>"
                    .utf8))
    }

    func testMixedRemovalChangesOneEpochWithoutInferringEndpointsOrOtherEdges() throws {
        var state = try EditorState(document: document())
        try state.selectGraph(nodes: ["a", "b"], edges: ["ab", "bc"])
        let before = state.snapshot
        try state.removeFromSelection(nodes: ["a"], edges: ["bc"])
        let after = state.snapshot
        XCTAssertEqual(after.selectedIDs, ["b"])
        XCTAssertEqual(after.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(after.selectedID, "b")
        XCTAssertEqual(after.selectionRevision, before.selectionRevision + 1)
        XCTAssertEqual(after.document.encoded(), before.document.encoded())
        XCTAssertEqual(after.documentRevision, before.documentRevision)
        XCTAssertEqual(after.previewIdentity, before.previewIdentity)
        XCTAssertEqual(after.constraintRevision, before.constraintRevision)
        XCTAssertFalse(after.canUndo)
        try state.removeFromSelection(nodes: ["b"], edges: [])
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab"])
        try state.removeFromSelection(nodes: [], edges: ["ab"])
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertNil(state.snapshot.selectedID)
    }

    func testEmptyAndUnselectedHitsPreserveEpochRevealAndNonGraphInspection() throws {
        var state = try EditorState(document: document())
        try state.selectWholePart(.part("p"))
        let revealed = state.snapshot
        XCTAssertNotNil(revealed.componentRevealHint)
        try state.removeFromSelection(nodes: [], edges: [])
        XCTAssertEqual(state.snapshot.componentRevealHint, revealed.componentRevealHint)
        XCTAssertEqual(state.snapshot.selectionRevision, revealed.selectionRevision)
        try state.selectGraph(nodes: ["a"], edges: ["ab"])
        let graph = state.snapshot
        try state.removeFromSelection(nodes: ["c"], edges: ["bc"])
        XCTAssertEqual(state.snapshot.selectedIDs, graph.selectedIDs)
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, graph.selectedEdgeIDs)
        XCTAssertEqual(state.snapshot.selectionRevision, graph.selectionRevision)
        try state.selectPart("p")
        let part = state.snapshot
        try state.removeFromSelection(nodes: ["a"], edges: ["ab"])
        XCTAssertEqual(state.snapshot.selectedPartID, part.selectedPartID)
        XCTAssertEqual(state.snapshot.selectionRevision, part.selectionRevision)
        try state.selectComponent("group")
        let component = state.snapshot
        try state.removeFromSelection(nodes: ["b"], edges: ["bc"])
        XCTAssertEqual(state.snapshot.selectedComponentIDs, component.selectedComponentIDs)
        XCTAssertEqual(state.snapshot.selectionRevision, component.selectionRevision)
        XCTAssertEqual(state.snapshot.document.encoded(), component.document.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testUnknownIdentitiesRejectAtomicallyEvenWhenNotSelected() throws {
        var state = try EditorState(document: document())
        try state.selectWholePart(.part("p"))
        let before = state.snapshot
        XCTAssertThrowsError(try state.removeFromSelection(nodes: ["a", "missing"], edges: ["ab"])) {
            XCTAssertEqual($0 as? DocumentError, .missingNode("missing"))
        }
        XCTAssertThrowsError(try state.removeFromSelection(nodes: ["a"], edges: ["absent"])) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
        XCTAssertEqual(state.snapshot.selectedIDs, before.selectedIDs)
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision)
        XCTAssertEqual(state.snapshot.componentRevealHint, before.componentRevealHint)
        try state.selectComponent("group")
        let component = state.snapshot
        XCTAssertThrowsError(try state.removeFromSelection(nodes: ["missing"], edges: []))
        XCTAssertEqual(state.snapshot.selectedComponentIDs, component.selectedComponentIDs)
        XCTAssertEqual(state.snapshot.selectionRevision, component.selectionRevision)
    }

    func testRemovalRequiresExactUTF8SourceIdentityWithoutCanonicalAlias() throws {
        let composed = "\u{e9}"
        let decomposed = "e\u{301}"
        var state = try EditorState(document: document(nodeID: composed))
        try state.selectGraph(nodes: [composed], edges: ["ab"])
        let before = state.snapshot
        XCTAssertThrowsError(try state.removeFromSelection(nodes: [decomposed], edges: [])) {
            guard case .missingNode(let id) = $0 as? DocumentError else {
                return XCTFail("Expected exact-identity missing node error")
            }
            XCTAssertEqual(Data(id.utf8), Data(decomposed.utf8))
        }
        XCTAssertEqual(state.snapshot.selectedIDs.map { Data($0.utf8) }, before.selectedIDs.map { Data($0.utf8) })
        XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision)
        try state.removeFromSelection(nodes: [composed], edges: [])
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab"])
    }

    func testActorRoutePreservesExistingHistoryAndRejectsInvalidRemovalAtomically() async throws {
        let session = EditorSession()
        let original = try document().encoded()
        _ = try await session.open(data: original)
        _ = try await session.selectGraph(nodes: ["a", "b"], edges: ["bc"])
        let edited = try await session.moveSelection(by: .init(x: 0.25, y: 0, z: 0))
        let removed = try await session.removeFromSelection(nodes: ["a"], edges: ["bc"])
        XCTAssertEqual(removed.selectedIDs, ["b"])
        XCTAssertTrue(removed.selectedEdgeIDs.isEmpty)
        XCTAssertEqual(removed.selectionRevision, edited.selectionRevision + 1)
        XCTAssertEqual(removed.document.encoded(), edited.document.encoded())
        XCTAssertEqual(removed.previewIdentity, edited.previewIdentity)
        XCTAssertEqual(removed.documentRevision, edited.documentRevision)
        XCTAssertTrue(removed.canUndo)
        do {
            _ = try await session.removeFromSelection(nodes: ["b"], edges: ["absent"])
            XCTFail("Invalid removal must reject before changing selection")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let unchanged = try await session.removeFromSelection(nodes: [], edges: [])
        XCTAssertEqual(unchanged.selectedIDs, removed.selectedIDs)
        XCTAssertEqual(unchanged.selectionRevision, removed.selectionRevision)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original)
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), edited.document.encoded())
    }
}
