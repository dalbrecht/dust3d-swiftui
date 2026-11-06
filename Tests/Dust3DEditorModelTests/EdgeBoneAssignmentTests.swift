import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EdgeBoneAssignmentTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='c' partId='q' x='.3' y='.5' z='.5' radius='.1'/><node id='d' partId='q' x='.4' y='.5' z='.5' radius='.1'/><node id='x' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e1' partId='p' from='a' to='b' boneName='Café'/><edge id='e2' partId='q' from='c' to='d' boneName='Cafe&#769;'/><edge id='e3' partId='p' from='b' to='x' boneName='Other'/></edges><parts><part id='p'/><part id='q'/></parts><future value='keep'/></canvas>"
                    .utf8))
    }

    func testMixedDraftRequiresActualEditAndKeepsByteDistinctNames() throws {
        var state = try EditorState(document: source())
        try state.selectGraph(nodes: ["x"], edges: ["e1", "e2"])
        let target = EdgeBoneAssignmentTarget(snapshot: state.snapshot)
        XCTAssertTrue(target.isCurrent(in: state.snapshot))
        XCTAssertEqual(target.selectedCount, 2)
        XCTAssertNil(target.commonName)
        var draft = EdgeBoneNameDraft(target: target)
        XCTAssertFalse(draft.canSubmit)
        draft.edit(BoneNameIdentity(""))
        XCTAssertFalse(draft.canSubmit, "Submitting an unchanged mixed blank must not clear assignments")
        draft.edit(BoneNameIdentity("Root"))
        XCTAssertTrue(draft.canSubmit)
        draft.edit(BoneNameIdentity(""))
        XCTAssertTrue(draft.canSubmit, "Typing then clearing is explicit intent")
        draft.reset()
        XCTAssertFalse(draft.canSubmit)
        try state.selectGraph(nodes: [], edges: ["e1"])
        let single = EdgeBoneAssignmentTarget(snapshot: state.snapshot, edgeIDs: ["e1"])
        XCTAssertEqual(single.commonName, BoneNameIdentity("Café"))
        XCTAssertFalse(single.hasChanges(name: "Café"))
        XCTAssertTrue(single.hasChanges(name: "Cafe\u{301}"))
        XCTAssertFalse(
            EdgeBoneAssignmentTarget(snapshot: state.snapshot, edgeIDs: ["e2"]).isCurrent(in: state.snapshot))
    }

    func testCapturedBatchIsOneUndoAndPreservesExplicitSelectionLocksAndNoOpRedo() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectGraph(nodes: ["x"], edges: ["e1", "e2"])
        let selected = try await session.setLock(.x, isLocked: true)
        let target = EdgeBoneAssignmentTarget(snapshot: selected)
        let changed = try await session.assignBoneName(" Left ", target: target)
        XCTAssertEqual(changed.selectedIDs, ["x"])
        XCTAssertEqual(changed.selectedEdgeIDs, ["e1", "e2"])
        XCTAssertEqual(changed.locks, [.x])
        XCTAssertEqual(changed.nodes, selected.nodes)
        XCTAssertEqual(changed.documentRevision, selected.documentRevision + 1)
        XCTAssertTrue(
            changed.edges.filter { ["e1", "e2"].contains($0.id) }.allSatisfy { $0.hasExactBoneName(" Left ") })
        XCTAssertTrue(try XCTUnwrap(changed.edges.first { $0.id == "e3" }).hasExactBoneName("Other"))
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        let other = try await session.selectGraph(nodes: [], edges: ["e3"])
        let noop = try await session.assignBoneName("Other", target: EdgeBoneAssignmentTarget(snapshot: other))
        XCTAssertEqual(noop.documentRevision, other.documentRevision)
        XCTAssertTrue(noop.canRedo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
    }

    func testStaleAndInitiallyUnavailableTargetsNeverRetargetAcrossABAUndoReplacementOrWindows() async throws {
        for change in 0..<5 {
            let original = try source()
            let session = EditorSession()
            let empty = try await session.open(data: original.encoded())
            let unavailable = EdgeBoneAssignmentTarget(snapshot: empty)
            let selected = try await session.selectGraph(nodes: [], edges: ["e1", "e2"])
            XCTAssertFalse(unavailable.isCurrent(in: selected))
            let target = EdgeBoneAssignmentTarget(snapshot: selected)
            var destination = session
            switch change {
            case 0:
                _ = try await session.selectGraph(nodes: [], edges: ["e3"])
                _ = try await session.selectGraph(nodes: [], edges: ["e1", "e2"])
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2:
                _ = try await session.apply([.setEdgeBoneName(id: "e3", name: "Changed")])
                _ = try await session.undo()
            case 3:
                _ = try await session.open(data: original.encoded())
                _ = try await session.selectGraph(nodes: [], edges: ["e1", "e2"])
            default:
                destination = EditorSession()
                _ = try await destination.open(data: original.encoded())
                _ = try await destination.selectGraph(nodes: [], edges: ["e1", "e2"])
            }
            let before = try await destination.selectGraph(nodes: [], edges: ["e1", "e2"])
            do {
                _ = try await destination.assignBoneName("Wrong", target: target)
                XCTFail("Stale batch")
            } catch { XCTAssertEqual(error as? EdgeBoneAssignmentError, .staleTarget) }
            let after = try await destination.selectGraph(nodes: [], edges: ["e1", "e2"])
            XCTAssertEqual(after.document.encoded(), before.document.encoded())
            XCTAssertEqual(after.documentRevision, before.documentRevision)
            XCTAssertEqual(after.canRedo, before.canRedo)
        }
    }

    func testCancellationAndInvalidNameKeepOriginalCauseAndState() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectGraph(nodes: [], edges: ["e1", "e2"])
        let target = EdgeBoneAssignmentTarget(snapshot: selected)
        do {
            _ = try await session.assignBoneName("bad\nname", target: target)
            XCTFail("Invalid name")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidBoneName) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.assignBoneName("Root", target: target)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled batch")
        } catch { XCTAssertTrue(error is CancellationError) }
        let after = try await session.selectGraph(nodes: [], edges: ["e1", "e2"])
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertEqual(after.documentRevision, selected.documentRevision)
        XCTAssertFalse(after.canUndo)
    }
}
