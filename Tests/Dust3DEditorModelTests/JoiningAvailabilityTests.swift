import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class JoiningAvailabilityTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ["a", "b", "c"].enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: "p", componentID: index == 0 ? "pc" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        document = try document.applying(.addEdge(id: "ab", from: "a", to: "b")).applying(
            .addEdge(id: "bc", from: "b", to: "c"))
        return try document.applying(
            .addNode(id: "target", partID: "q", componentID: "qc", position: .init(x: 3, y: 0, z: 0), radius: 0.1))
    }
    func testEndpointAvailabilityIncludesOtherPartsAndExcludesInteriorAndGroupExtension() throws {
        var state = try EditorState(document: document())
        XCTAssertTrue(state.snapshot.canAddNode)
        XCTAssertEqual(state.snapshot.connectableNodes.map(\.id), ["a", "c", "target"])
        try state.select("a")
        XCTAssertEqual(state.snapshot.connectionTargets.map(\.id), ["c", "target"])
        XCTAssertTrue(state.snapshot.canAddNode)
        try state.select("b")
        XCTAssertTrue(state.snapshot.connectionTargets.isEmpty)
        XCTAssertFalse(state.snapshot.canAddNode)
        try state.select(["a", "c"])
        XCTAssertFalse(state.snapshot.canAddNode)
        XCTAssertTrue(state.snapshot.connectionTargets.isEmpty)
    }
    @MainActor func testActorJoinConsumesPartAndUndoRestoresBoth() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select("c")
        _ = try await session.setLock(.x, isLocked: true)
        let joined = try await session.apply([.joinNodes(id: "join", from: "c", to: "target")])
        XCTAssertEqual(Set(joined.nodes.compactMap(\.partID)), ["p"])
        XCTAssertEqual(joined.selectedID, "c")
        XCTAssertTrue(joined.locks.contains(.x))
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
        XCTAssertFalse(restored.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), joined.document.encoded())
    }
    func testSuggestedExtensionMovesAwayFromNeighborAndHandlesSingleOrCoincidentNodes() throws {
        var state = try EditorState(document: document())
        XCTAssertEqual(state.snapshot.nextNodePosition, .init(x: 0.5, y: 0.5, z: 0.5))
        try state.select("a")
        XCTAssertEqual(state.snapshot.nextNodePosition, .init(x: -0.25, y: 0, z: 0))
        try state.select("c")
        XCTAssertEqual(state.snapshot.nextNodePosition, .init(x: 2.25, y: 0, z: 0))
        try state.select("target")
        XCTAssertEqual(state.snapshot.nextNodePosition, .init(x: 3, y: 0.25, z: 0))
        try state.edit(id: "a", position: .init(x: 1, y: 0, z: 0), radius: 0.1)
        XCTAssertEqual(state.snapshot.nextNodePosition, .init(x: 1, y: 0.25, z: 0))
    }

    @MainActor func testFailedJoinBatchNeverPublishesConsumedPartOrHistory() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.select("c")
        do {
            _ = try await session.apply([
                .joinNodes(id: "join", from: "c", to: "target"), .joinNodes(id: "bad", from: "missing", to: "a"),
            ])
            XCTFail("Invalid batch must fail")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let result = try await session.select("c")
        XCTAssertEqual(result.document.encoded(), original.encoded())
        XCTAssertFalse(result.canUndo)
        XCTAssertEqual(result.selectedID, "c")
    }

    @MainActor func testDeletionThenJoinNormalizesTheSurvivingPart() async throws {
        var original = try document()
        for (index, id) in ["q2", "q3"].enumerated() {
            original = try original.applying(
                .addNode(
                    id: id, partID: "q", componentID: nil,
                    position: .init(x: 4 + Double(index), y: 0, z: 0), radius: 0.1))
        }
        original = try original.applying(.addEdge(id: "tq2", from: "target", to: "q2"))
            .applying(.addEdge(id: "q2q3", from: "q2", to: "q3"))
            .applying(.addEdge(id: "q3t", from: "q3", to: "target"))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let joined = try await session.apply([
            .removeEdge(id: "q3t"), .joinNodes(id: "join", from: "c", to: "target"),
        ])
        XCTAssertEqual(Set(joined.nodes.compactMap(\.partID)), ["p"])
        XCTAssertEqual(joined.edges.count, 5)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
        XCTAssertFalse(restored.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), joined.document.encoded())
    }

}
