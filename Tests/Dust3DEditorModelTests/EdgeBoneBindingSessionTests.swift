import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class EdgeBoneBindingSessionTests: XCTestCase {
    func testBoneBindingsUseAtomicSessionHistoryWithoutChangingSelectionOrLocks() async throws {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        document = try document.applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        document = try document.applying(
            .addNode(id: "b", partID: "p", componentID: nil, position: .init(x: 1, y: 0, z: 0), radius: 0.1))
        document = try document.applying(.addEdge(id: "e", from: "a", to: "b"))
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        _ = try await session.selectEdge("e")
        _ = try await session.setLock(.x, isLocked: true)
        let changed = try await session.apply([.setEdgeBoneName(id: "e", name: "Root")])
        XCTAssertEqual(changed.selectedEdge?.boneName, "Root")
        XCTAssertEqual(changed.selectedEdgeID, "e")
        XCTAssertEqual(changed.locks, [.x])
        XCTAssertEqual(changed.nodes, try document.editorContents().nodes)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), document.encoded())
        XCTAssertEqual(undone.selectedEdge?.boneName, "")
        let noop = try await session.apply([.setEdgeBoneName(id: "e", name: "")])
        XCTAssertTrue(noop.canRedo)
        XCTAssertEqual(noop.documentRevision, undone.documentRevision)
        do {
            _ = try await session.apply([
                .setEdgeBoneName(id: "e", name: "Partial"), .setEdgeBoneName(id: "missing", name: "Root"),
            ])
            XCTFail("Reject the whole binding batch")
        } catch {
            XCTAssertEqual(error as? DocumentError, .invalidNode)
        }
        let restored = try await session.redo()
        XCTAssertEqual(restored.document.encoded(), changed.document.encoded())
        XCTAssertEqual(restored.selectedEdge?.boneName, "Root")
    }
}
