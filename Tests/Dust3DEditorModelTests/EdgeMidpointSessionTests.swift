import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EdgeMidpointSessionTests: XCTestCase {
    private func document(locked: Bool = false) throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        document = try document.applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        document = try document.applying(
            .addNode(id: "b", partID: "p", componentID: nil, position: .init(x: 1, y: 0, z: 0), radius: 0.3))
        document = try document.applying(.addEdge(id: "e", from: "a", to: "b"))
        if locked { document = try document.applying(.setPartState(id: "p", property: .locked, value: true)) }
        return document
    }

    func testMidpointAvailabilityRejectsReadOnlyAndMissingSelections() throws {
        for locked in [false, true] {
            var state = try EditorState(document: document(locked: locked))
            XCTAssertFalse(state.snapshot.canInsertSelectedEdgeMidpoint)
            try state.selectEdge("e")
            XCTAssertEqual(state.snapshot.canInsertSelectedEdgeMidpoint, !locked)
        }
    }

    func testHiddenAndDisabledEndpointsDisableMidpointInsertion() throws {
        for (property, value) in [(PartStateProperty.visible, false), (.disabled, true)] {
            let original = try document().applying(.setPartState(id: "p", property: property, value: value))
            var state = try EditorState(document: original)
            try state.selectEdge("e")
            XCTAssertFalse(state.snapshot.canInsertSelectedEdgeMidpoint)
            XCTAssertThrowsError(try state.insertSelectedEdgeMidpoint(nodeID: "mid", edgeID: "new"))
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testMidpointAvailabilityRejectsMalformedEdgeOwnershipAndSelfLoops() throws {
        for (from, to, part) in [("a", "a", "p"), ("a", "b", "q"), ("a", "c", "p"), ("a", "missing", "p")] {
            let xml = """
                <canvas><nodes>
                <node id="a" partId="p" x="0" y="0" z="0" radius="0.1"/>
                <node id="b" partId="p" x="1" y="0" z="0" radius="0.1"/>
                <node id="c" partId="q" x="1" y="1" z="0" radius="0.1"/>
                </nodes><parts><part id="p"/><part id="q"/></parts>
                <edges><edge id="e" partId="\(part)" from="\(from)" to="\(to)"/></edges></canvas>
                """
            let model = Data(xml.utf8)
            let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
            let prefix = "DUST3D 1.0 xml "
            let archive =
                Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model
            let document = try Dust3DDocument(data: archive)
            if to == "missing" {
                XCTAssertThrowsError(
                    try EditorState(document: document), "Missing endpoints reject when opening the editor")
                continue
            }
            var state = try EditorState(document: document)
            try state.selectEdge("e")
            XCTAssertFalse(state.snapshot.canInsertSelectedEdgeMidpoint)
            XCTAssertThrowsError(try state.insertSelectedEdgeMidpoint(nodeID: "mid", edgeID: "new"))
            XCTAssertEqual(state.snapshot.document.encoded(), archive)
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testSelectedEdgeMidpointAllocatesIdentitiesAndUsesOneUndoStep() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectEdge("e")
        let changed = try await session.insertSelectedEdgeMidpoint()
        XCTAssertEqual(changed.selectedEdgeID, "e")
        XCTAssertTrue(changed.selectedIDs.isEmpty)
        XCTAssertEqual(changed.nodes.count, 3)
        XCTAssertEqual(changed.edges.count, 2)
        let midpoint = try XCTUnwrap(changed.nodes.first { $0.id != "a" && $0.id != "b" })
        XCTAssertEqual(midpoint.value.position.x, 0.5)
        XCTAssertTrue(midpoint.id.hasPrefix("{"))
        XCTAssertNotEqual(midpoint.id, changed.edges.first { $0.id != "e" }?.id)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertEqual(undone.selectedEdgeID, "e")
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
    }

    func testMissingAndReadOnlySelectionRejectWithoutChangingHistory() throws {
        for locked in [false, true] {
            let original = try document(locked: locked)
            var state = try EditorState(document: original)
            if locked { try state.selectEdge("e") }
            XCTAssertThrowsError(try state.insertSelectedEdgeMidpoint(nodeID: "mid", edgeID: "new"))
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }
}
