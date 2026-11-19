import AppKit
import Dust3DDocument
import Dust3DKit
import XCTest

@testable import Dust3DEditor

private struct QtCopyNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

final class QtClipboardStoreTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Qt clipboard paste did not settle")
    }

    @MainActor func testQtCopyWritesOnlyTextAndLeavesSourceAndUndoUntouched() async throws {
        let node = "{11111111-1111-4111-8111-111111111111}"
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: node, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = EditorStore(preview: QtCopyNoPreview())
        defer { store.stop() }
        await store.load(data: document.encoded())
        try await settle(store)
        store.selectGraph(nodes: [node], edges: [])
        try await settle(store)
        store.copyNodesAsQtXML(to: EditorPasteboard(pasteboard: board))
        try await settle(store)
        let text = try XCTUnwrap(board.string(forType: .string))
        let exported = try Dust3DDocument(snapshotXML: Data(text.utf8))
        XCTAssertEqual(try exported.editorContents().nodes.map(\.id), [node])
        XCTAssertEqual(board.pasteboardItems?.first?.types, [.string])
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
    }

    @MainActor func testQtPastePublishesDocumentPreviewAndExactUndoWithAtomicFailure() async throws {
        let empty = Dust3DDocument.emptyArchive()
        let source = try Dust3DDocument(data: empty).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: empty)
        try await settle(store)
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }
        store.pasteQtNodes(snapshotXML: source.modelXML)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.selectedIDs.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(store.mesh?.triangleCount), 0)
        XCTAssertEqual(writes.count, 1)
        let pasted = store.snapshot?.document.encoded()
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), empty)
        XCTAssertTrue(store.canRedo)
        let count = writes.count
        store.pasteQtNodes(snapshotXML: Data("plain unrelated text".utf8))
        try await settle(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.document.encoded(), empty)
        XCTAssertEqual(writes.count, count)
        XCTAssertTrue(store.canRedo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), pasted)
    }
}
