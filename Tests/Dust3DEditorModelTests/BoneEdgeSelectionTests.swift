import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class BoneEdgeSelectionTests: XCTestCase {
    private func source(name: String = "é", sourceLocked: Bool = false, peerLocked: Bool = false) throws
        -> Dust3DDocument
    {
        let rows: [(String, String, String, String)] = [
            ("anchor", "p", "p", name), ("peer", "q", "q", name), ("decomposed", "q", "q", "e\u{301}"),
            ("case", "q", "q", "É"), ("space", "q", "q", name + " "), ("locked", "locked", "locked", name),
            ("hidden", "hidden", "hidden", name), ("disabled", "disabled", "disabled", name),
            ("unsupported", "café", "q", name), ("ownerLocked", "q", "locked", name),
        ]
        let nodes = rows.map { id, nodePart, _, _ in
            "<node id='\(id)a' partId='\(nodePart)' x='.2' y='.5' z='.5' radius='.1'/><node id='\(id)b' partId='\(nodePart)' x='.4' y='.5' z='.5' radius='.1'/>"
        }.joined()
        let edges = rows.map { id, _, edgePart, bone in
            "<edge id='\(id)' partId='\(edgePart)' from='\(id)a' to='\(id)b' boneName='\(bone)'/>"
        }.joined()
        return try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes>\(nodes)</nodes><edges>\(edges)</edges><parts><part id='p' locked='\(sourceLocked)'/><part id='q' locked='\(peerLocked)'/><part id='locked' locked='true'/><part id='hidden' visible='false'/><part id='disabled' disabled='true'/><part id='cafe&#769;'/></parts><future value='keep'/></canvas>"
                    .utf8))
    }

    func testSelectsExactEditableBoneEdgesAcrossPartsWithoutChangingHistory() async throws {
        for readonly in [false, true] {
            let original = try source(sourceLocked: readonly)
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            _ = try await session.apply([.setPartName(id: "q", name: "Change")])
            _ = try await session.undo()
            let selected = try await session.selectGraph(nodes: [], edges: ["anchor"])
            let target = GraphInspectorActionContext(snapshot: selected).target(for: .selectBoneEdges(edgeID: "anchor"))
            XCTAssertTrue(target.isCurrent(in: selected))
            XCTAssertFalse(target.changesDocument)
            let result = try await session.performInspectorAction(target: target)
            XCTAssertEqual(result.selectedEdgeIDs, readonly ? ["peer"] : ["anchor", "peer"])
            XCTAssertTrue(result.selectedIDs.isEmpty)
            XCTAssertNil(result.selectedPartID)
            XCTAssertTrue(result.selectedComponentIDs.isEmpty)
            XCTAssertEqual(result.document.encoded(), original.encoded())
            XCTAssertEqual(result.documentRevision, selected.documentRevision)
            XCTAssertFalse(result.canUndo)
            XCTAssertTrue(result.canRedo)
        }
    }

    func testRetainedBoneSelectionRejectsABAUndoReplacementAndOtherWindow() async throws {
        for change in 0..<5 {
            let original = try source()
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.selectGraph(nodes: [], edges: ["anchor"])
            let target = GraphInspectorActionContext(snapshot: selected).target(for: .selectBoneEdges(edgeID: "anchor"))
            var destination = session
            switch change {
            case 0:
                _ = try await session.selectGraph(nodes: [], edges: ["peer"])
                _ = try await session.selectGraph(nodes: [], edges: ["anchor"])
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2:
                _ = try await session.apply([.setEdgeBoneName(id: "peer", name: "Other")])
                _ = try await session.undo()
            case 3:
                _ = try await session.open(data: original.encoded())
                _ = try await session.selectGraph(nodes: [], edges: ["anchor"])
            default:
                destination = EditorSession()
                _ = try await destination.open(data: original.encoded())
                _ = try await destination.selectGraph(nodes: [], edges: ["anchor"])
            }
            let before = try await destination.selectGraph(nodes: [], edges: ["anchor"])
            do {
                _ = try await destination.performInspectorAction(target: target)
                XCTFail("Retained bone selection must reject changed intent")
            } catch { XCTAssertEqual(error as? GraphInspectorActionError, .staleTarget) }
            let after = try await destination.selectGraph(nodes: [], edges: ["anchor"])
            XCTAssertEqual(after.document.encoded(), before.document.encoded())
            XCTAssertEqual(after.documentRevision, before.documentRevision)
            XCTAssertEqual(after.canRedo, before.canRedo)
            XCTAssertEqual(after.selectedEdgeIDs, before.selectedEdgeIDs)
        }
    }

    func testEmptyUnavailableAndUnrelatedBoneTargetsNeverAcquireLaterIntent() async throws {
        for original in [try source(name: ""), try source(sourceLocked: true, peerLocked: true)] {
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.selectGraph(nodes: [], edges: ["anchor"])
            let context = GraphInspectorActionContext(snapshot: selected)
            let target = context.target(for: .selectBoneEdges(edgeID: "anchor"))
            XCTAssertFalse(target.isCurrent(in: selected))
            XCTAssertFalse(context.target(for: .selectBoneEdges(edgeID: "peer")).isCurrent(in: selected))
            _ = try await session.open(data: source().encoded())
            let current = try await session.selectGraph(nodes: [], edges: ["anchor"])
            XCTAssertFalse(target.isCurrent(in: current))
            do {
                _ = try await session.performInspectorAction(target: target)
                XCTFail("Unavailable target must stay unavailable")
            } catch { XCTAssertEqual(error as? GraphInspectorActionError, .staleTarget) }
            let nodes = try await session.selectGraph(nodes: ["anchora"], edges: ["anchor"])
            XCTAssertFalse(
                GraphInspectorActionContext(snapshot: nodes).target(for: .selectBoneEdges(edgeID: "anchor")).isCurrent(
                    in: nodes))
        }
    }

    func testRepeatedSingleMatchIsSelectionNoOpAndCancellationPublishesNothing() async throws {
        let session = EditorSession()
        let original = try source(peerLocked: true)
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectGraph(nodes: [], edges: ["anchor"])
        let target = GraphInspectorActionContext(snapshot: selected).target(for: .selectBoneEdges(edgeID: "anchor"))
        let result = try await session.performInspectorAction(target: target)
        XCTAssertEqual(result.selectionRevision, selected.selectionRevision)
        XCTAssertEqual(result.selectedEdgeIDs, ["anchor"])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.performInspectorAction(target: target)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled selection")
        } catch { XCTAssertTrue(error is CancellationError) }
        let after = try await session.selectGraph(nodes: [], edges: ["anchor"])
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertEqual(after.selectionRevision, result.selectionRevision)
        XCTAssertFalse(after.canUndo)
    }
}
