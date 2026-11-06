import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class BoneEdgeOverviewTests: XCTestCase {
    private func source(allAssigned: Bool = false) throws -> Dust3DDocument {
        let rows: [(String, String?, String, Bool)] = [
            ("root", "p", "Root", false), ("open", "p", "", false),
            ("hidden", "q", "", false), ("missing", "unknown", "", false),
            ("ownerless", nil, "", false), ("cut", "cut", "", false),
            ("cutNamed", "cut", "Root", false), ("badEndpoints", "p", "", true),
            ("future", "unknown", "Future", false), ("nfc", "p", "Café", false),
            ("nfd", "p", "Cafe\u{301}", false),
        ]
        let edges = rows.map { id, owner, name, bad in
            let ownership = owner.map { "partId='\($0)'" } ?? ""
            let bone = allAssigned && name.isEmpty ? "Root" : name
            return
                "<edge id='\(id)' \(ownership) from='\(bad ? "c" : "a")' to='\(bad ? "d" : "b")' boneName='\(bone)'/>"
        }.joined()
        return try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Biped'><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='c' partId='café' x='.3' y='.5' z='.5' radius='.1'/><node id='d' partId='café' x='.4' y='.5' z='.5' radius='.1'/></nodes><edges>\(edges)</edges><parts><part id='p'/><part id='q' visible='false'/><part id='cut' target='CutFace'/><part id='cafe&#769;'/></parts><future value='keep'/></canvas>"
                    .utf8))
    }

    func testProgressTotalsRawHighlightsAndSelectableIDsFollowDifferentQtRules() throws {
        let state = try EditorState(document: source())
        let overview = BoneEdgeOverview(snapshot: state.snapshot)
        XCTAssertEqual(overview.totalEdgeCount, 9)
        XCTAssertEqual(overview.assignedEdgeCount, 4)
        XCTAssertEqual(overview.unassignedEdgeCount, 5)
        let unassigned = overview.target(for: .unassigned)
        XCTAssertEqual(unassigned.matchingEdgeIDs, ["open", "hidden", "missing", "ownerless", "badEndpoints"])
        XCTAssertEqual(unassigned.selectableEdgeCount, 1)
        XCTAssertTrue(unassigned.isCurrent(in: state.snapshot))
        let named = overview.target(for: .named("Root"))
        XCTAssertEqual(named.matchingEdgeIDs, ["root", "cutNamed"])
        XCTAssertEqual(named.selectableEdgeCount, 2)
        XCTAssertEqual(overview.target(for: .named("Café")).matchingEdgeIDs, ["nfc"])
        XCTAssertEqual(overview.target(for: .named("Cafe\u{301}")).matchingEdgeIDs, ["nfd"])
        XCTAssertFalse(overview.target(for: .named("")).isAvailable)
    }

    func testSelectionReplacesMixedSetsPreservesDocumentRedoAndZeroNamedMatchesClear() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.apply([.setPartName(id: "p", name: "temporary")])
        _ = try await session.undo()
        let before = try await session.selectGraph(nodes: ["a"], edges: ["root"])
        let target = BoneEdgeOverview(snapshot: before).target(for: .unassigned)
        let selected = try await session.selectBoneEdges(target: target)
        XCTAssertEqual(selected.selectedEdgeIDs, ["open"])
        XCTAssertTrue(selected.selectedIDs.isEmpty)
        XCTAssertEqual(selected.document.encoded(), original.encoded())
        XCTAssertEqual(selected.documentRevision, before.documentRevision)
        XCTAssertFalse(selected.canUndo)
        XCTAssertTrue(selected.canRedo)
        let repeatTarget = BoneEdgeOverview(snapshot: selected).target(for: .unassigned)
        let repeated = try await session.selectBoneEdges(target: repeatTarget)
        XCTAssertEqual(repeated.selectionRevision, selected.selectionRevision)
        let zero = BoneEdgeOverview(snapshot: repeated).target(for: .named("No matching bone"))
        XCTAssertTrue(zero.isAvailable)
        let cleared = try await session.selectBoneEdges(target: zero)
        XCTAssertTrue(cleared.selectedIDs.isEmpty && cleared.selectedEdgeIDs.isEmpty)
        XCTAssertTrue(cleared.canRedo)
        XCTAssertEqual(cleared.documentRevision, before.documentRevision)
    }

    func testRetainedTargetsRejectSelectionConstraintUndoReplacementAndOtherWindowEpochs() async throws {
        for change in 0..<5 {
            let original = try source()
            let session = EditorSession()
            let before = try await session.open(data: original.encoded())
            let target = BoneEdgeOverview(snapshot: before).target(for: .unassigned)
            var destination = session
            switch change {
            case 0:
                _ = try await session.selectGraph(nodes: ["a"], edges: ["root"])
                _ = try await session.selectGraph(nodes: [], edges: [])
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2:
                _ = try await session.apply([.setPartName(id: "p", name: "temporary")])
                _ = try await session.undo()
            case 3: _ = try await session.open(data: original.encoded())
            default:
                destination = EditorSession()
                _ = try await destination.open(data: original.encoded())
            }
            let prior = try await destination.apply([])
            do {
                _ = try await destination.selectBoneEdges(target: target)
                XCTFail("Stale selection")
            } catch { XCTAssertEqual(error as? BoneEdgeSelectionError, .staleTarget) }
            let after = try await destination.apply([])
            XCTAssertEqual(after.document.encoded(), prior.document.encoded())
            XCTAssertEqual(after.selectedEdgeIDs, prior.selectedEdgeIDs)
            XCTAssertEqual(after.selectionRevision, prior.selectionRevision)
            XCTAssertEqual(after.canRedo, prior.canRedo)
        }
    }

    func testAllAssignedEmptyAndCancelledIntentNeverAcquireLaterMatches() async throws {
        let session = EditorSession()
        let assigned = try await session.open(data: source(allAssigned: true).encoded())
        let overview = BoneEdgeOverview(snapshot: assigned)
        XCTAssertEqual(overview.assignedEdgeCount, overview.totalEdgeCount)
        let unavailable = overview.target(for: .unassigned)
        XCTAssertFalse(unavailable.isAvailable)
        let current = try await session.open(data: source().encoded())
        do {
            _ = try await session.selectBoneEdges(target: unavailable)
            XCTFail("Unavailable acquired matches")
        } catch { XCTAssertEqual(error as? BoneEdgeSelectionError, .staleTarget) }
        let target = BoneEdgeOverview(snapshot: current).target(for: .unassigned)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.selectBoneEdges(target: target)
        }
        do {
            _ = try await operation.value
            XCTFail("Cancellation ignored")
        } catch { XCTAssertTrue(error is CancellationError) }
        let after = try await session.apply([])
        XCTAssertEqual(after.selectionRevision, current.selectionRevision)
        XCTAssertEqual(after.document.encoded(), current.document.encoded())
        let empty = try EditorState(
            document: Dust3DDocument(snapshotXML: Data("<canvas><nodes/><edges/><parts/></canvas>".utf8)))
        let emptyOverview = BoneEdgeOverview(snapshot: empty.snapshot)
        XCTAssertEqual(emptyOverview.totalEdgeCount, 0)
        XCTAssertFalse(emptyOverview.target(for: .unassigned).isAvailable)
    }
}
