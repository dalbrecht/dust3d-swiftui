import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class ComponentOrderStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Component ordering or generation did not settle")
    }
    @MainActor func testReorderRegeneratesPreviewPublishesOneEditAndKeepsSelectionAndCamera() async throws {
        let first = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
        let last = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        var original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (node, part, component, x) in [
            ("{11111111-1111-4111-8111-111111111111}", "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", first, 0.5),
            ("{22222222-2222-4222-8222-222222222222}", "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", last, 3.0),
        ] {
            original = try original.applying(
                .addNode(
                    id: node, partID: part, componentID: component, position: .init(x: x, y: 0.5, z: 0.5), radius: 0.1))
        }
        let store = EditorStore()
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertFalse(store.canReorderComponent(.up))
        store.reorderComponent(.up)
        store.selectComponent(last)
        try await settle(store)
        XCTAssertTrue(store.canReorderComponent(.up))
        XCTAssertFalse(store.canReorderComponent(.down))
        let camera = store.cameraReset
        let preview = store.previewRevision
        let noop = try XCTUnwrap(store.beginComponentDrag(grabbedID: last))
        XCTAssertFalse(store.dropComponents(token: noop, at: .after(last)))
        XCTAssertFalse(store.dropComponents(token: noop, at: .before(first)))
        let token = try XCTUnwrap(store.beginComponentDrag(grabbedID: last))
        XCTAssertFalse(store.dropComponents(token: UUID(), at: .before(first)))
        XCTAssertTrue(store.dropComponents(token: token, at: .before(first)))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), [last, first])
        XCTAssertEqual(store.snapshot?.selectedComponentID, last)
        XCTAssertEqual(publications, 1)
        XCTAssertGreaterThan(store.previewRevision, preview)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        let edited = store.snapshot?.document.encoded()
        let completedPreview = store.previewRevision
        XCTAssertFalse(store.dropComponents(token: token, at: .after(first)))
        try await settle(store)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.previewRevision, completedPreview)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), edited)
        XCTAssertEqual(store.mesh?.triangleCount, 32)
        store.stop()
        XCTAssertFalse(store.canReorderComponent(.down))
    }

    @MainActor func testParentDropRejectsInvalidAndNoOpTargetsAndMovesTheEntireBlockInSourceOrder() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a'/><component id='group'><component id='b'/><component id='x'/></component></components></canvas>"
                    .utf8))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)

        let noOp = try XCTUnwrap(store.beginComponentDrag(grabbedID: "group"))
        XCTAssertFalse(store.dropComponents(token: noOp, in: .root))
        XCTAssertFalse(store.isWorking)
        let cycle = try XCTUnwrap(store.beginComponentDrag(grabbedID: "group"))
        XCTAssertFalse(store.dropComponents(token: cycle, in: .component("b")))
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.canUndo)

        store.selectComponents(["a", "b"])
        try await settle(store)
        let block = try XCTUnwrap(store.beginComponentDrag(grabbedID: "a"))
        XCTAssertTrue(store.dropComponents(token: block, in: .component("group")))
        let proposal = try XCTUnwrap(store.pendingComponentGroupDrop)
        XCTAssertTrue(store.confirmComponentGroupDrop(proposal.id))
        try await settle(store)
        let result = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(result.componentTree.rows.map(\.id), ["group", "x", "a", "b"])
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
    }

    @MainActor func testListEndReordersOnlySiblingsAndRejectsRetiredScopes() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components>
                <component id='a'/><component id='b'/>
                <component id='g'><component id='x'/><component id='y'/><component id='z'/></component>
                </components></canvas>
                """.utf8))
        let original = source.encoded()
        let store = EditorStore()
        let other = EditorStore()
        defer {
            store.stop()
            other.stop()
        }
        await store.load(data: original)
        await other.load(data: original)
        try await settle(store)
        try await settle(other)
        let disclosure = ComponentSidebarDisclosure()
        let initial = try XCTUnwrap(store.snapshot)
        let staleDisclosure = store.componentListEndDropAction(snapshot: initial, disclosure: disclosure)
        disclosure.collapsedIDs = ["g"]
        disclosure.collapsedIDs = []
        let noOp = try XCTUnwrap(store.beginComponentDrag(grabbedID: "g"))
        XCTAssertFalse(staleDisclosure(noOp))
        let root = store.componentListEndDropAction(snapshot: initial, disclosure: disclosure)
        XCTAssertFalse(root(noOp))
        XCTAssertFalse(store.canUndo)
        let child = try XCTUnwrap(store.beginComponentDrag(grabbedID: "x"))
        XCTAssertFalse(root(child))
        XCTAssertFalse(store.isWorking)

        store.selectComponents(["b", "a"])
        try await settle(store)
        let block = try XCTUnwrap(store.beginComponentDrag(grabbedID: "a"))
        let foreign = other.componentListEndDropAction(
            snapshot: try XCTUnwrap(other.snapshot), disclosure: ComponentSidebarDisclosure())
        XCTAssertFalse(foreign(block))
        XCTAssertTrue(root(block))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), ["g", "x", "y", "z", "a", "b"])
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, ["a", "b"])
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)

        store.componentBrowseAction("g", snapshot: try XCTUnwrap(store.snapshot))()
        try await settle(store)
        XCTAssertEqual(store.componentGroupBrowse?.path.last?.id, "g")
        store.selectComponents(["y", "x"])
        try await settle(store)
        let scoped = store.componentListEndDropAction(
            snapshot: try XCTUnwrap(store.snapshot), disclosure: disclosure)
        let scopedBlock = try XCTUnwrap(store.beginComponentDrag(grabbedID: "x"))
        XCTAssertFalse(root(scopedBlock))
        XCTAssertTrue(scoped(scopedBlock))
        try await settle(store)
        XCTAssertEqual(store.componentGroupBrowse?.children.map(\.id), ["z", "x", "y"])
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, ["x", "y"])
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    @MainActor func testInteriorSiblingChoicesAndPlacementForSingleAndMultipleRows() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a'/><component id='b'/><component id='c'/><component id='d'><component id='child'/></component><component id='e'/></components></canvas>"
                    .utf8))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)

        store.selectComponent("e")
        try await settle(store)
        var snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(ComponentBatchOrderMenu.eligibleSiblings(in: snapshot).map(\.id), ["a", "b", "c", "d"])
        let single = try XCTUnwrap(ComponentPlacementTarget(snapshot: snapshot))
        store.placeComponents(at: .before("c"), target: single)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), ["a", "b", "e", "c", "d", "child"])

        store.selectComponents(["a", "d", "child"])
        try await settle(store)
        snapshot = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(ComponentBatchOrderMenu.eligibleSiblings(in: snapshot).map(\.id), ["b", "e", "c"])
        let batch = try XCTUnwrap(ComponentPlacementTarget(snapshot: snapshot))
        store.placeComponents(at: .after("e"), target: batch)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.componentTree.rows.map(\.id), ["b", "e", "a", "d", "child", "c"])
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), snapshot.document.encoded())

        store.selectComponents(["a", "child"])
        try await settle(store)
        XCTAssertTrue(ComponentBatchOrderMenu.eligibleSiblings(in: try XCTUnwrap(store.snapshot)).isEmpty)
    }
}
