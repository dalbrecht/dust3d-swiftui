import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class GraphTransformTests: XCTestCase {
    private func document(locked: Bool = true, visible: Bool = true) throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='keep'><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='0.1' future='retain'/><node id='b' partId='p' x='2' y='4' z='6' radius='0.2'/><node id='c' partId='q' x='4' y='6' z='8' radius='0.3'/></nodes><edges><edge id='e' from='a' to='b' partId='p' future='edge'><future/></edge><edge id='r' from='b' to='c'/></edges><parts><part id='p'/><part id='q' locked='\(locked)' visible='\(visible)'/></parts></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='2'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255]))
    }

    func testEveryTransformUsesEditableCentroidAndExactUndo() throws {
        let original = try document()
        let expected: [SelectionTransform: NodePosition] = [
            .frontClockwise: .init(x: 3, y: 1, z: 0),
            .frontCounterclockwise: .init(x: -1, y: 3, z: 0),
            .sideClockwise: .init(x: 0, y: -1, z: 5),
            .sideCounterclockwise: .init(x: 0, y: 5, z: 1),
            .flipX: .init(x: 2, y: 0, z: 0),
            .flipY: .init(x: 0, y: 4, z: 0),
            .flipZ: .init(x: 0, y: 0, z: 6),
            .exchangeXZ: .init(x: 0, y: 0, z: 0),
        ]
        XCTAssertEqual(expected.count, SelectionTransform.allCases.count)
        for transform in SelectionTransform.allCases {
            XCTAssertFalse(transform.rawValue.isEmpty)
            var state = try EditorState(document: original)
            state.selectAll()
            try state.transformSelection(transform)
            XCTAssertEqual(try state.snapshot.document.node(id: "a").position, expected[transform])
            XCTAssertEqual(try state.snapshot.document.node(id: "a").radius, 0.1)
            XCTAssertEqual(try state.snapshot.document.node(id: "c"), try original.node(id: "c"))
            XCTAssertEqual(state.snapshot.document.asset(named: "opaque"), Data([0, 255]))
            let edited = state.snapshot.document.encoded()
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
            try state.redo()
            XCTAssertEqual(state.snapshot.document.encoded(), edited)
            XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c"])
        }
    }

    func testPositionLocksApplyExceptExplicitExchangeMatchingQt() throws {
        let original = try document()
        for transform in SelectionTransform.allCases {
            var state = try EditorState(document: original)
            try state.select(["a", "b"])
            for lock in EditingConstraint.allCases { state.setLock(lock, isLocked: true) }
            try state.transformSelection(transform)
            if transform == .exchangeXZ {
                XCTAssertEqual(try state.snapshot.document.node(id: "b").position, .init(x: 6, y: 4, z: 2))
            } else {
                XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
                XCTAssertFalse(state.snapshot.canUndo)
            }
            XCTAssertEqual(state.snapshot.locks, Set(EditingConstraint.allCases))
        }
    }

    func testEmptyReadOnlySingleAndOutOfBoundsTransforms() throws {
        var state = try EditorState(document: document())
        for transform in SelectionTransform.allCases { try state.transformSelection(transform) }
        try state.select("c")
        for transform in SelectionTransform.allCases { try state.transformSelection(transform) }
        XCTAssertFalse(state.snapshot.canUndo)
        try state.select("a")
        try state.transformSelection(.frontClockwise)
        XCTAssertFalse(state.snapshot.canUndo)
        try state.edit(id: "a", position: .init(x: 1_000_000, y: -1_000_000, z: 0), radius: 0.1)
        try state.edit(id: "b", position: .init(x: 1_000_000, y: 1_000_000, z: 0), radius: 0.2)
        try state.select(["a", "b"])
        let before = state.snapshot.document.encoded()
        XCTAssertThrowsError(try state.transformSelection(.frontClockwise))
        XCTAssertEqual(state.snapshot.document.encoded(), before)
        state.setLock(.x, isLocked: true)
        try state.transformSelection(.frontClockwise)
        XCTAssertEqual(try state.snapshot.document.node(id: "b").position, .init(x: 1_000_000, y: 0, z: 0))
    }

    func testBulkEdgeReversalPreservesUnknownDataAndNetZeroHistory() throws {
        let original = try document()
        XCTAssertEqual(try original.applying(.reverseEdges([])).encoded(), original.encoded())
        XCTAssertThrowsError(try original.applying(.reverseEdges(["e", "e"])))
        XCTAssertThrowsError(try original.applying(.reverseEdges(["e", "missing"])))
        XCTAssertThrowsError(try original.applying(.reverseEdges(["e", "r"])))
        let reversed = try original.applying(.reverseEdges(["e"]))
        let edge = try reversed.editorContents().edges[0]
        XCTAssertEqual(edge.fromID, "b")
        XCTAssertEqual(edge.toID, "a")
        let xml = try XMLDocument(data: reversed.modelXML)
        let element = try XCTUnwrap(try xml.nodes(forXPath: "//edge[@id='e']").first as? XMLElement)
        XCTAssertEqual(element.attribute(forName: "future")?.stringValue, "edge")
        XCTAssertEqual(element.elements(forName: "future").count, 1)
        XCTAssertEqual(reversed.asset(named: "opaque"), Data([0, 255]))
        var history = DocumentHistory(document: original)
        try history.beginTransaction()
        try history.apply(.reverseEdges(["e"]))
        try history.apply(.reverseEdges(["e"]))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
    }

    func testEdgeAvailabilityRequiresBothEndpointsForLockedAndHiddenParts() throws {
        for (locked, visible) in [(true, true), (false, false), (false, true)] {
            let original = try document(locked: locked, visible: visible)
            var state = try EditorState(document: original)
            try state.select("b")
            let expected = !locked && visible ? ["e", "r"] : ["e"]
            XCTAssertEqual(state.snapshot.editableEdges.map(\.id), expected)
            XCTAssertTrue(state.snapshot.reversibleEdges.isEmpty)
            state.selectAll()
            XCTAssertEqual(state.snapshot.reversibleEdges.map(\.id), expected)
            if locked || !visible {
                XCTAssertThrowsError(try state.apply([.reverseEdges(["r"])]))
                XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            } else {
                try state.apply([.reverseEdges(["r"])])
                XCTAssertEqual(state.snapshot.edges[1].fromID, "c")
            }
        }
    }

    @MainActor func testSelectionReversalAndActorTransforms() async throws {
        let original = try document()
        var state = try EditorState(document: original)
        XCTAssertEqual(state.snapshot.editableEdges.map(\.id), ["e"])
        try state.reverseSelectedEdges()
        state.selectAll()
        XCTAssertEqual(state.snapshot.reversibleEdges.map(\.id), ["e"])
        try state.reverseSelectedEdges()
        XCTAssertEqual(state.snapshot.edges[0].fromID, "b")
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectAll()
        let transformed = try await session.transformSelection(.frontClockwise)
        XCTAssertEqual(try transformed.document.node(id: "a").position, .init(x: 3, y: 1, z: 0))
        let reversed = try await session.reverseSelectedEdges()
        XCTAssertEqual(reversed.edges[0].fromID, "b")
    }
}
