import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

/// Reads only the existing licensed Sword archive. Never instantiates a geometry service.
@MainActor
final class EdgeDirectionRepairArchiveTests: XCTestCase {
    private let first = "{95153ae7-a9a1-55cd-9cba-87c62bd25dbb}"
    private let middle = "{8dd66dbc-f2f1-555c-bb73-1a21ee649ac6}"

    func testExplicitRepairOfNormallyReversedSwordPreservesPassiveOpenAndOneUndo() async throws {
        let original = try sword()
        let edited = EditorSession()
        _ = try await edited.open(data: original)
        let reversed = try await edited.apply([.reverseEdges([middle])])
        let inconsistent = reversed.document.encoded()
        XCTAssertNotEqual(inconsistent, original)

        let session = EditorSession()
        let opened = try await session.open(data: inconsistent)
        XCTAssertEqual(opened.document.encoded(), inconsistent)
        XCTAssertFalse(opened.canUndo)
        let selected = try await session.selectGraph(nodes: [], edges: [middle])
        let target = GraphInspectorActionContext(snapshot: selected).target(for: .repairEdgeDirections(edgeID: middle))
        XCTAssertTrue(target.isCurrent(in: selected))
        XCTAssertTrue(target.changesDocument)
        let repaired = try await session.performInspectorAction(target: target)
        XCTAssertEqual(repaired.selectedEdgeIDs, [middle])
        XCTAssertTrue(repaired.canUndo)
        XCTAssertEqual(repaired.edges, try Dust3DDocument(data: original).editorContents().edges)
        let expected = try reversed.document.applying(.reverseEdges([middle])).encoded()
        XCTAssertEqual(repaired.document.encoded(), expected)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Repaired Sword.ds3")
        let files = DocumentFileService()
        try await files.save(repaired.document, to: destination)
        let reopened = try await files.load(from: destination)
        XCTAssertEqual(reopened.encoded(), expected)
        XCTAssertEqual(try reopened.editorContents().edges, repaired.edges)

        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), inconsistent)
        XCTAssertFalse(undone.canUndo)
        try await assertRejected(target, in: session)
        _ = try await session.open(data: inconsistent)
        _ = try await session.selectGraph(nodes: [], edges: [middle])
        try await assertRejected(target, in: session)
    }

    func testDirectionRepairRejectsCoherentAmbiguousAndStaleSelection() async throws {
        let session = EditorSession()
        _ = try await session.open(data: sword())
        let coherent = try await session.selectGraph(nodes: [], edges: [middle])
        let coherentTarget = GraphInspectorActionContext(snapshot: coherent)
            .target(for: .repairEdgeDirections(edgeID: middle))
        XCTAssertFalse(coherentTarget.isCurrent(in: coherent))
        try await assertRejected(coherentTarget, in: session)

        let reversed = try await session.apply([.reverseEdges([middle])])
        let repairable = GraphInspectorActionContext(snapshot: reversed)
            .target(for: .repairEdgeDirections(edgeID: middle))
        XCTAssertTrue(repairable.isCurrent(in: reversed))
        _ = try await session.selectGraph(nodes: [], edges: [first])
        _ = try await session.selectGraph(nodes: [], edges: [middle])
        try await assertRejected(repairable, in: session)

        let ambiguous = try await session.apply([.reverseEdges([first])])
        let ambiguousTarget = GraphInspectorActionContext(snapshot: ambiguous)
            .target(for: .repairEdgeDirections(edgeID: middle))
        XCTAssertFalse(ambiguousTarget.isCurrent(in: ambiguous))
        try await assertRejected(ambiguousTarget, in: session)
    }

    private func sword() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Sword", withExtension: "ds3", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func assertRejected(_ target: GraphInspectorActionTarget, in session: EditorSession) async throws {
        do {
            _ = try await session.performInspectorAction(target: target)
            XCTFail("Expected stale or unavailable repair")
        } catch let error as GraphInspectorActionError {
            XCTAssertEqual(error, .staleTarget)
        }
    }
}
