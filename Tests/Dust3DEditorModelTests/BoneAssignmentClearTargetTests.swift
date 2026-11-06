import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class BoneAssignmentClearTargetTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Biped'><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e1' partId='p' from='a' to='b' boneName='Café'/><edge id='e2' partId='unknown' from='b' to='a' boneName='Cafe&#769;'/></edges><parts><part id='p' locked='true'/></parts></canvas>"
                    .utf8))
    }
    func testExactNamesReadonlyScopeOneUndoAndInitiallyEmptyIntent() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.selectGraph(nodes: ["a"], edges: ["e2"])
        XCTAssertEqual(before.selectedIDs, ["a"])
        XCTAssertEqual(before.selectedEdgeIDs, ["e2"])
        let empty = BoneAssignmentClearTarget(snapshot: before, names: ["Missing", ""])
        XCTAssertFalse(empty.isAvailable)
        let target = BoneAssignmentClearTarget(snapshot: before, names: ["Café"])
        XCTAssertEqual(target.matchingEdgeCount, 1)
        XCTAssertTrue(target.isCurrent(in: before))
        let cleared = try await session.clearBoneAssignments(target: target)
        XCTAssertEqual(cleared.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(cleared.selectedIDs, before.selectedIDs)
        XCTAssertTrue(try XCTUnwrap(cleared.edges.first { $0.id == "e1" }).boneName.isEmpty)
        XCTAssertTrue(try XCTUnwrap(cleared.edges.first { $0.id == "e2" }).hasExactBoneName("Cafe\u{301}"))
        XCTAssertEqual(cleared.nodes, before.nodes)
        XCTAssertEqual(cleared.documentRevision, before.documentRevision + 1)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        XCTAssertTrue(undone.canRedo)
        XCTAssertFalse(target.isCurrent(in: undone))
        do {
            _ = try await session.clearBoneAssignments(target: empty)
            XCTFail("Initially unavailable target acquired later intent")
        } catch { XCTAssertEqual(error as? BoneAssignmentClearError, .staleTarget) }
    }
    func testCancellationAndSelectionConstraintReplacementOrWindowABAReject() async throws {
        let original = try source()
        for change in 0..<5 {
            let session = EditorSession()
            let before = try await session.open(data: original.encoded())
            let target = BoneAssignmentClearTarget(snapshot: before, names: ["Café", "Cafe\u{301}"])
            switch change {
            case 0:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 1:
                _ = try await session.selectGraph(nodes: [], edges: ["e1"])
                _ = try await session.selectGraph(nodes: [], edges: [])
            case 2: _ = try await session.open(data: original.encoded())
            case 3:
                let other = EditorSession()
                _ = try await other.open(data: original.encoded())
                do {
                    _ = try await other.clearBoneAssignments(target: target)
                    XCTFail("Wrong window")
                } catch { XCTAssertEqual(error as? BoneAssignmentClearError, .staleTarget) }
                continue
            default:
                let operation = Task {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try await session.clearBoneAssignments(target: target)
                }
                do {
                    _ = try await operation.value
                    XCTFail("Cancellation ignored")
                } catch { XCTAssertTrue(error is CancellationError) }
                let observed = try await session.apply([])
                XCTAssertEqual(observed.document.encoded(), original.encoded())
                continue
            }
            do {
                _ = try await session.clearBoneAssignments(target: target)
                XCTFail("Stale action")
            } catch { XCTAssertEqual(error as? BoneAssignmentClearError, .staleTarget) }
            let observed = try await session.apply([])
            XCTAssertEqual(observed.document.encoded(), original.encoded())
        }
    }
}
