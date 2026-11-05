import Dust3DDocument
import XCTest

final class BatchEdgeRemovalTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
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

    func testBatchRemovesCapturedEdgesAndRetainsNodesWithOneUndoStep() throws {
        let original = try document()
        var history = DocumentHistory(document: original)
        try history.apply(.removeEdges(["cd", "ab"]))
        XCTAssertEqual(try history.document.editorContents().edges.map(\.id), ["bc"])
        XCTAssertEqual(try history.document.editorContents().nodes, try original.editorContents().nodes)
        history.undo()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        history.redo()
        XCTAssertEqual(try history.document.editorContents().edges.map(\.id), ["bc"])
    }

    func testBatchRejectsMissingDuplicateReadonlyAndOversizedRequestsAtomically() throws {
        let original = try document()
        for ids in [["ab", "missing"], ["ab", "ab"]] {
            var history = DocumentHistory(document: original)
            XCTAssertThrowsError(try history.apply(.removeEdges(ids))) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertFalse(history.canUndo)
        }
        let readonly = try original.applying(.setPartState(id: "p", property: .locked, value: true))
        XCTAssertThrowsError(try readonly.applying(.removeEdges(["ab", "bc"]))) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
        XCTAssertThrowsError(try original.applying(.removeEdges(Array(repeating: "ab", count: 20_001)))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        var history = DocumentHistory(document: original)
        try history.apply(.removeEdges([]))
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
    }
}
