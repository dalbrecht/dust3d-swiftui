import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

private struct WrappingClipboardNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor final class WrappingClipboardStoreTests: XCTestCase {
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Clipboard store did not settle")
    }
    func testStoreNativeAndQtPasteRouteBindingOnceWithWindowIsolationAndExactUndo() async throws {
        // Existing independently authored positive one-sphere wrapping fixture; preview is deliberately not invoked.
        let original = try WrappingFixture.document(
            mode: "Cloth", attributes: "wrapFaces='64' wrapBindTo='external body'")
        let nodeIDs = Set(try original.editorContents().nodes.map(\.id))
        let clipboard = try original.copyingNodes(nodeIDs)
        let payload = try NodeClipboardPayload(fragment: clipboard, identifier: "binding-store").encoded()
        for qt in [false, true] {
            let store = EditorStore(preview: WrappingClipboardNoPreview())
            let other = EditorStore(preview: WrappingClipboardNoPreview())
            defer {
                store.stop()
                other.stop()
            }
            await store.load(data: original.encoded())
            await other.load(data: original.encoded())
            try await settle(store)
            try await settle(other)
            var writes: [Data] = []
            store.onDocumentChanged = { writes.append($0) }
            if qt {
                store.pasteQtNodes(snapshotXML: clipboard.document.modelXML)
            } else {
                store.pasteNodes(data: payload)
            }
            try await settle(store)
            XCTAssertNil(store.errorMessage)
            let pasted = try XCTUnwrap(store.snapshot)
            XCTAssertEqual(pasted.selectedIDs.count, 1)
            XCTAssertTrue(pasted.selectedIDs.isDisjoint(with: nodeIDs))
            XCTAssertEqual(writes.count, 1)
            XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
            let xml = try XMLDocument(data: pasted.document.modelXML)
            let groups = xml.rootElement()?.elements(forName: "components").first?.elements(forName: "component") ?? []
            let fresh = try XCTUnwrap(
                groups.first { $0.attribute(forName: "id")?.stringValue != WrappingFixture.groupID })
            XCTAssertEqual(fresh.attribute(forName: "wrapBindTo")?.stringValue, "external body")
            XCTAssertEqual(pasted.document.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(store.canUndo)
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), pasted.document.encoded())
        }
    }
}
