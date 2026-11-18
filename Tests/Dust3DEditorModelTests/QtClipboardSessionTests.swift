import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class QtClipboardSessionTests: XCTestCase {
    @MainActor func testQtPasteSelectsFreshEditableEdgesForImmediateMidpointButNativePasteSelectsNodesOnly()
        async throws
    {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas>
                  <nodes>
                    <node id="a" partId="p" x="0" y="0" z="0" radius=".1"/>
                    <node id="b" partId="p" x="1" y="0" z="0" radius=".1"/>
                  </nodes>
                  <edges><edge id="ab" partId="p" from="a" to="b"/></edges>
                  <parts><part id="p"/></parts>
                  <components><component id="c" linkDataType="partId" linkData="p"/></components>
                </canvas>
                """.utf8))
        let session = EditorSession()
        let before = try await session.open(data: original.encoded())
        let pasted = try await session.pasteQtXMLFile(original.modelXML, target: .init(snapshot: before))
        let edge = try XCTUnwrap(pasted.edges.first { $0.id != "ab" })
        XCTAssertEqual(pasted.selectedIDs, [edge.fromID, edge.toID])
        XCTAssertEqual(pasted.selectedEdgeIDs, [edge.id])
        XCTAssertTrue(pasted.canInsertSelectedEdgeMidpoints)
        let inserted = try await session.insertSelectedEdgeMidpoints()
        XCTAssertEqual(inserted.edges.count, 3)
        let restoredPaste = try await session.undo()
        XCTAssertEqual(restoredPaste.document.encoded(), pasted.document.encoded())
        let restoredSource = try await session.undo()
        XCTAssertEqual(restoredSource.document.encoded(), original.encoded())
        XCTAssertFalse(restoredSource.canUndo)

        let fragment = try original.copyingNodes(["a", "b"])
        let payload = try NodeClipboardPayload(fragment: fragment, identifier: "native").encoded()
        let native = try await session.paste(data: payload)
        XCTAssertEqual(native.selectedIDs.count, 2)
        XCTAssertTrue(native.selectedEdgeIDs.isEmpty)
        XCTAssertEqual(native.edges.count, 2)
    }

    @MainActor func testQtPasteLeavesHiddenLockedAndDisabledGeometryUnselected() async throws {
        let parts = [
            ("editable", ""), ("hidden", "visible='false'"), ("locked", "locked='true'"),
            ("disabled", "disabled='true'"),
        ]
        let nodes = parts.map { name, _ in
            """
            <node id="\(name)a" partId="\(name)" x="0" y="0" z="0" radius=".1"/>
            <node id="\(name)b" partId="\(name)" x="1" y="0" z="0" radius=".1"/>
            """
        }.joined()
        let edges = parts.map { name, _ in
            "<edge id='\(name)edge' partId='\(name)' from='\(name)a' to='\(name)b'/>"
        }.joined()
        let owners = parts.map { "<part id='\($0.0)' \($0.1)/>" }.joined()
        let components = parts.map { "<component id='\($0.0)c' linkDataType='partId' linkData='\($0.0)'/>" }.joined()
        let xml = Data(
            """
            <canvas><nodes>\(nodes)</nodes><edges>\(edges)</edges><parts>\(owners)</parts>
            <components>\(components)</components></canvas>
            """.utf8)
        let session = EditorSession()
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        let pasted = try await session.paste(snapshotXML: xml)
        XCTAssertEqual(pasted.nodes.count, 8)
        XCTAssertEqual(pasted.edges.count, 4)
        let edge = try XCTUnwrap(pasted.editableEdges.first)
        XCTAssertEqual(pasted.selectedIDs, [edge.fromID, edge.toID])
        XCTAssertEqual(pasted.selectedEdgeIDs, [edge.id])
    }

    @MainActor func testRepeatedQtPastesAreAtomicUndoableAndResetOnOpen() async throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let first = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(first.selectedNodes.first?.value.position.y, 0.04)
        let second = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(second.selectedNodes.first?.value.position.y, 0.08)
        _ = try await session.undo()
        do {
            _ = try await session.paste(snapshotXML: Data("<canvas/>".utf8))
            XCTFail("Empty Qt clipboard must reject")
        } catch {}
        let restored = try await session.redo()
        XCTAssertEqual(restored.document.encoded(), second.document.encoded())
        let third = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(third.selectedNodes.first?.value.position.y, 0.12)
        _ = try await session.open(data: source.encoded())
        let reset = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(reset.selectedNodes.first?.value.position.y, 0.04)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        _ = try await session.select("a")
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0])
        _ = try await session.apply([.setReferenceImagePNG(png)])
        let representations = try await session.copyRepresentations(identifier: "copy")
        XCTAssertEqual(try NodeClipboardPayload(data: representations.native).fragment.document.referenceImagePNG, png)
        XCTAssertNil(try Dust3DDocument(snapshotXML: representations.snapshotXML).referenceImagePNG)
        XCTAssertEqual(
            try NodeClipboardPayload(data: representations.native).fragment.document.modelXML,
            representations.snapshotXML)
        XCTAssertEqual(try Dust3DDocument(snapshotXML: representations.snapshotXML).editorContents().nodes.count, 1)
    }
}
