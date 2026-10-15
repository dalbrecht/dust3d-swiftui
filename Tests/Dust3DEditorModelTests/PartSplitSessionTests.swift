import Dust3DDocument
import Dust3DEditorModel
import XCTest

@MainActor final class PartSplitSessionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ["a", "b", "c"].enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: "p", componentID: index == 0 ? "comp" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        document = try document.applying(.addEdge(id: "ab", from: "a", to: "b"))
        return try document.applying(.addEdge(id: "bc", from: "b", to: "c"))
    }

    func testDisconnectSplitsPartInOneUndoStepAndRedoRetainsIdentities() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select("b")
        let split = try await session.apply([.removeEdge(id: "ab")])
        let parts = Set(split.nodes.compactMap(\.partID))
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(split.nodes.first { $0.id == "b" }?.partID, "p")
        XCTAssertEqual(split.nodes.first { $0.id == "c" }?.partID, "p")
        XCTAssertEqual(split.selectedID, "b")
        XCTAssertTrue(try split.document.partSplitRequirements(for: parts).isEmpty)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), split.document.encoded())
    }

    func testSelectionDeletionAndDirectNodeDeletionNormalizeOnlyAffectedParts() async throws {
        for bulk in [false, true] {
            let original = try document()
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            _ = try await session.select("b")
            let split = try await (bulk ? session.deleteSelection() : session.apply([.removeNode(id: "b")]))
            XCTAssertEqual(split.nodes.count, 2)
            XCTAssertEqual(Set(split.nodes.compactMap(\.partID)).count, 2)
            XCTAssertTrue(split.edges.isEmpty)
            XCTAssertNil(split.selectedID)
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), original.encoded())
            XCTAssertFalse(undone.canUndo)
        }
    }

    func testInvalidBatchNoOpAndLastNodeDeletionPreserveAtomicity() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        do {
            _ = try await session.apply([.removeEdge(id: "ab"), .removeEdge(id: "missing")])
            XCTFail("Invalid removal should fail atomically")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let unchanged = try await session.select(nil)
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertFalse(unchanged.canUndo)
        _ = try await session.apply([.removeEdge(id: "ab")])
        _ = try await session.undo()
        let noOp = try await session.deleteSelection()
        XCTAssertTrue(noOp.canRedo)
        _ = try await session.selectAll()
        let empty = try await session.deleteSelection()
        XCTAssertTrue(empty.nodes.isEmpty)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
    }
    func testUnrelatedDisconnectedPartIsNotNormalizedByMixedBatch() async throws {
        var original = try document()
        original = try original.applying(
            .addNode(id: "q1", partID: "q", componentID: "qc", position: .init(x: 5, y: 0, z: 0), radius: 0.1))
        original = try original.applying(
            .addNode(id: "q2", partID: "q", componentID: nil, position: .init(x: 6, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let result = try await session.apply([
            .setNode(id: "a", position: .init(x: 0, y: 1, z: 0), radius: 0.1), .removeEdge(id: "ab"),
        ])
        XCTAssertEqual(result.nodes.filter { $0.partID == "q" }.map(\.id), ["q1", "q2"])
        XCTAssertEqual(try result.document.partSplitRequirements(for: ["q"]).count, 1)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
    }

}
