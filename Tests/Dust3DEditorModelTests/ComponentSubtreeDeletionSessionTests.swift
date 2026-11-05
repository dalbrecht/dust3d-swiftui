import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor final class ComponentSubtreeDeletionSessionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='n' partId='p' x='.3' y='.3' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' locked='true' disabled='true' visible='false'/></parts><components><component id='g' linkDataType='future' linkData='opaque'><component id='leaf' linkDataType='partId' linkData='p'/></component><component id='b'/><component id='keep'/></components></canvas>
                """.utf8))
    }
    func testManagementDeletionHasOneUndoOneSelectionEpochAndNoSelectionResurrection() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectComponents(["g", "leaf"])
        let target = ComponentDeletionTarget(snapshot: selected)
        XCTAssertEqual(target.rootCount, 1)
        XCTAssertTrue(target.isCurrent(in: selected))
        let changed = try await session.deleteComponentSubtrees(target: target)
        XCTAssertTrue(changed.selectedComponentIDs.isEmpty)
        XCTAssertTrue(changed.nodes.isEmpty)
        XCTAssertTrue(changed.parts.isEmpty)
        XCTAssertEqual(changed.selectionRevision, selected.selectionRevision + 1)
        XCTAssertNotEqual(changed.previewIdentity.geometry, selected.previewIdentity.geometry)
        XCTAssertNotEqual(changed.previewIdentity.materials, selected.previewIdentity.materials)
        let undone = try await session.undo()
        XCTAssertTrue(undone.document.hasSameEditingState(as: original))
        XCTAssertTrue(undone.selectedComponentIDs.isEmpty)
        XCTAssertFalse(undone.canUndo)
        XCTAssertEqual(undone.previewIdentity, selected.previewIdentity)
    }
    func testExplicitContextRowDeletesItselfRatherThanEarlierSelectionAndKeepsUnrelatedSelection() async throws {
        let session = EditorSession()
        _ = try await session.open(data: source().encoded())
        let selected = try await session.selectComponents(["keep"])
        let context = ComponentDeletionTarget(snapshot: selected, componentIDs: ["b"])
        let changed = try await session.deleteComponentSubtrees(target: context)
        XCTAssertEqual(changed.selectedComponentIDs, ["keep"])
        XCTAssertEqual(changed.selectionRevision, selected.selectionRevision)
        XCTAssertEqual(changed.componentTree.rows.map(\.id), ["g", "leaf", "keep"])
        XCTAssertEqual(changed.nodes.map(\.id), ["n"])
    }
    func testCapturedTargetsRejectSelectionConstraintsRevisionReplacementAndOtherWindows() async throws {
        let original = try source()
        for change in 0..<5 {
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.selectComponents(["g"])
            let target = ComponentDeletionTarget(snapshot: selected, componentIDs: ["b"])
            switch change {
            case 0:
                _ = try await session.selectComponents(["b"])
                _ = try await session.selectComponents(["g"])
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2:
                _ = try await session.apply([.setComponentName(id: "keep", name: "changed")])
                _ = try await session.undo()
            case 3:
                _ = try await session.open(data: original.encoded())
                _ = try await session.selectComponents(["g"])
            default:
                let other = EditorSession()
                _ = try await other.open(data: original.encoded())
                _ = try await other.selectComponents(["g"])
                do {
                    _ = try await other.deleteComponentSubtrees(target: target)
                    XCTFail("Cross-window deletion")
                } catch { XCTAssertEqual(error as? ComponentDeletionError, .staleTarget) }
                continue
            }
            do {
                _ = try await session.deleteComponentSubtrees(target: target)
                XCTFail("Stale deletion")
            } catch { XCTAssertEqual(error as? ComponentDeletionError, .staleTarget) }
            let current = try await session.selectComponents(["g"])
            XCTAssertEqual(current.document.encoded(), original.encoded())
            XCTAssertFalse(current.canUndo)
        }
    }
    func testUnavailableAndCancelledTargetsNeverAcquireLaterValidIntent() async throws {
        let session = EditorSession()
        let original = try source()
        let initial = try await session.open(data: original.encoded())
        let unavailable = ComponentDeletionTarget(snapshot: initial)
        let selected = try await session.selectComponents(["g"])
        XCTAssertFalse(unavailable.isCurrent(in: selected))
        let invalid = ComponentDeletionTarget(snapshot: selected, componentIDs: ["missing"])
        XCTAssertEqual(invalid.rootCount, 0)
        do {
            _ = try await session.deleteComponentSubtrees(target: invalid)
            XCTFail("Invalid captured target")
        } catch { XCTAssertEqual(error as? ComponentDeletionError, .staleTarget) }
        let target = ComponentDeletionTarget(snapshot: selected)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.deleteComponentSubtrees(target: target)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled deletion")
        } catch { XCTAssertTrue(error is CancellationError) }
        let current = try await session.selectComponents(["g"])
        XCTAssertEqual(current.document.encoded(), original.encoded())
        XCTAssertFalse(current.canUndo)
    }
    func testDefaultTargetDoesNotCanonicalizeAnEarlierSelectionAliasIntoARealRow() async throws {
        let actual = "owner-cafe\u{301}"
        let missing = "owner-caf\u{e9}"
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='owner-cafe&#769;'/></components></canvas>
                """.utf8))
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        // Existing generic selection accepts Swift-canonical aliases; a destructive target must not infer one.
        let selected = try await session.selectComponents([missing])
        let target = ComponentDeletionTarget(snapshot: selected)
        XCTAssertEqual(target.rootCount, 0)
        XCTAssertFalse(target.isCurrent(in: selected))
        let mixed = ComponentDeletionTarget(snapshot: selected, componentIDs: [actual, missing])
        XCTAssertFalse(mixed.isCurrent(in: selected))
        XCTAssertTrue(ComponentDeletionTarget(snapshot: selected, componentIDs: [actual]).isCurrent(in: selected))
    }

    func testManySelectedLeavesUnderDeepSharedParentsAndSelectedAncestorsCountOnlyOutermostRoots() async throws {
        let leaves = (0..<128).map { "leaf-\($0)" }
        var components = leaves.map { "<component id='\($0)'/>" }.joined()
        for depth in (0..<64).reversed() {
            components = "<component id='parent-\(depth)'>\(components)</component>"
        }
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components>\(components)</components></canvas>".utf8))
        let session = EditorSession()
        let snapshot = try await session.open(data: document.encoded())
        XCTAssertEqual(ComponentDeletionTarget(snapshot: snapshot, componentIDs: leaves).rootCount, 128)
        XCTAssertEqual(ComponentDeletionTarget(snapshot: snapshot, componentIDs: leaves + ["parent-32"]).rootCount, 1)
        XCTAssertEqual(
            ComponentDeletionTarget(snapshot: snapshot, componentIDs: leaves + ["parent-32", "parent-0"]).rootCount, 1)
        XCTAssertEqual(snapshot.document.encoded(), document.encoded())
        XCTAssertFalse(snapshot.canUndo)
    }

}
