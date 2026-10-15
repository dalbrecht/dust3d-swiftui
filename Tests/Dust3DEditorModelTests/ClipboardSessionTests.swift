import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ClipboardSessionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ["a", "b", "c"].enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: "p", componentID: index == 0 ? "component" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        return try document.applying(.addEdge(id: "ab", from: "a", to: "b")).applying(
            .addEdge(id: "bc", from: "b", to: "c"))
    }
    @MainActor func testCopyAndNormalizedPasteUseOneUndoAndSelectOnlyFreshNodes() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select(["a", "c"])
        let copied = try await session.copySelection()
        let data = try NodeClipboardPayload(fragment: copied, identifier: "copy-1").encoded()
        let decoded = try NodeClipboardPayload(data: data)
        XCTAssertEqual(decoded.identifier, "copy-1")
        XCTAssertEqual(decoded.fragment.document.encoded(), copied.document.encoded())
        XCTAssertEqual(decoded.fragment.selectedNodeIDs, ["a", "c"])
        let pasted = try await session.paste(data: data)
        XCTAssertEqual(pasted.nodes.count, 5)
        XCTAssertEqual(pasted.selectedIDs.count, 2)
        XCTAssertTrue(pasted.selectedIDs.isDisjoint(with: ["a", "b", "c"]))
        XCTAssertEqual(Set(pasted.nodes.compactMap(\.partID)).count, 3)
        XCTAssertTrue(pasted.selectedNodes.allSatisfy { $0.value.position.y == 0.04 && $0.value.position.z == 0.04 })
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), pasted.document.encoded())
    }
    @MainActor func testRepeatedExternalPastesUseFreshIDsAndIncrementPlacement() async throws {
        let original = try document()
        let clipboard = try original.copyingNodes(["a", "b"])
        let data = try NodeClipboardPayload(fragment: clipboard, identifier: "external").encoded()
        let session = EditorSession()
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        let first = try await session.paste(data: data)
        XCTAssertTrue(first.selectedNodes.allSatisfy { $0.value.position.y == 0 })
        let second = try await session.paste(data: data)
        XCTAssertTrue(second.selectedIDs.isDisjoint(with: first.selectedIDs))
        XCTAssertTrue(second.selectedNodes.allSatisfy { $0.value.position.y == 0.04 })
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        let reopened = try await session.paste(data: data)
        XCTAssertTrue(reopened.selectedNodes.allSatisfy { $0.value.position.y == 0 })
    }
    private func archive(_ model: Data) throws -> Dust3DDocument {
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }
    @MainActor func testReadonlyPartialCopyPartitionsNewPartsWithoutUnlockingSource() async throws {
        let original = try document()
        let model = try XMLDocument(data: original.modelXML)
        let attribute = XMLNode(kind: .attribute)
        attribute.name = "locked"
        attribute.stringValue = "true"
        model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part").first?.addAttribute(attribute)
        let locked = try archive(model.xmlData(options: [.nodePreserveAll]))
        let source = EditorSession()
        let initial = try await source.open(data: locked.encoded())
        XCTAssertFalse(initial.canCopyNodes)
        XCTAssertFalse(initial.canCutNodes)
        let selection = try await source.select(["a", "c"])
        XCTAssertTrue(selection.canCopyNodes)
        XCTAssertFalse(selection.canCutNodes)
        let data = try await source.copyPayload(identifier: "locked")
        let target = EditorSession()
        _ = try await target.open(data: Dust3DDocument.emptyArchive())
        let pasted = try await target.paste(data: data)
        XCTAssertEqual(Set(pasted.nodes.compactMap(\.partID)).count, 2)
        XCTAssertTrue(pasted.nodes.allSatisfy { !$0.isEditable })
        XCTAssertEqual(pasted.selectedIDs.count, 2)
        let unchanged = try await source.select(["a", "c"])
        XCTAssertEqual(unchanged.document.encoded(), locked.encoded())
        XCTAssertFalse(unchanged.canUndo)
        let undone = try await target.undo()
        XCTAssertEqual(undone.document.encoded(), Dust3DDocument.emptyArchive())
    }
    @MainActor func testCutPreparationExcludesReadonlyNodesAndDeletionKeepsTheirSelection() async throws {
        let original = try document()
        let model = try XMLDocument(data: original.modelXML)
        let attribute = XMLNode(kind: .attribute)
        attribute.name = "locked"
        attribute.stringValue = "true"
        model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part").first?.addAttribute(attribute)
        let mixed = try archive(model.xmlData(options: [.nodePreserveAll])).applying(
            .addNode(id: "editable", partID: "q", componentID: "qc", position: .init(x: 4, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: mixed.encoded())
        let selected = try await session.select(["a", "editable"])
        XCTAssertTrue(selected.canCopyNodes)
        XCTAssertTrue(selected.canCutNodes)
        let copied = try await session.copySelection(onlyEditable: true)
        XCTAssertEqual(copied.selectedNodeIDs, ["editable"])
        let deleted = try await session.deleteSelection()
        XCTAssertEqual(deleted.selectedIDs, ["a"])
        XCTAssertEqual(try deleted.document.node(id: "a"), try mixed.node(id: "a"))
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), mixed.encoded())
    }
    @MainActor func testClipboardFailuresRetainDocumentHistorySelectionAndPlacement() async throws {
        let original = try document()
        let session = EditorSession()
        do {
            _ = try await session.copySelection()
            XCTFail("Unloaded copy must fail")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        do {
            _ = try await session.paste(data: Data())
            XCTFail("Unloaded paste must fail")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        _ = try await session.open(data: original.encoded())
        _ = try await session.select("a")
        let data = try await session.copyPayload(identifier: "same")
        _ = try await session.paste(data: data)
        let undone = try await session.undo()
        do {
            _ = try await session.paste(data: Data("invalid".utf8))
            XCTFail("Invalid paste must fail")
        } catch { XCTAssertEqual(error as? ClipboardError, .invalidPayload) }
        let boundary = try original.applying(.setNode(id: "a", position: .init(x: 0, y: 1_000_000, z: 0), radius: 0.1))
            .copyingNodes(["a"])
        let overflowing = try NodeClipboardPayload(fragment: boundary, identifier: "same").encoded()
        do {
            _ = try await session.paste(data: overflowing)
            XCTFail("Overflowing geometry must fail")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let retained = try await session.select("a")
        XCTAssertEqual(retained.document.encoded(), undone.document.encoded())
        XCTAssertEqual(retained.selectedIDs, ["a"])
        XCTAssertTrue(retained.canRedo)
        let pasted = try await session.paste(data: data)
        XCTAssertTrue(pasted.selectedNodes.allSatisfy { $0.value.position.y == 0.08 })
        XCTAssertFalse(pasted.canRedo)
        _ = try await session.select(nil)
        do {
            _ = try await session.copySelection()
            XCTFail("Empty copy must fail")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let unassigned = try archive(
            Data("<canvas><nodes><node id='u' x='0' y='0' z='0' radius='.1'/></nodes></canvas>".utf8))
        var state = try EditorState(document: unassigned)
        try state.select("u")
        XCTAssertFalse(state.snapshot.canCopyNodes)
        XCTAssertFalse(state.snapshot.canCutNodes)
    }

    @MainActor func testProfileDependencyNodesArePastedButNotSelected() async throws {
        let xml =
            "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1' cutFace='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}'/><node id='profile' partId='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' x='1' y='0' z='0' radius='.1'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/><part id='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' target='CutFace'/></parts></canvas>"
        let original = try archive(Data(xml.utf8))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select("a")
        let payload = try await session.copyPayload(identifier: "profile-copy")
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        _ = try await session.setLock(.x, isLocked: true)
        let pasted = try await session.paste(data: payload)
        XCTAssertEqual(pasted.nodes.count, 2)
        XCTAssertEqual(pasted.selectedIDs.count, 1)
        XCTAssertEqual(pasted.selectedNode?.value.position.x, 0)
        XCTAssertTrue(pasted.locks.contains(.x))
        XCTAssertEqual(Set(pasted.nodes.compactMap(\.partID)).count, 2)
    }

}
