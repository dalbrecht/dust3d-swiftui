import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

@MainActor
final class GraphSelectionActionTests: XCTestCase {
    private func document(locked: Bool = false) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas future='retained'><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='.5' y='0' z='0' radius='.2'/>
                <node id='c' partId='p' x='1' y='0' z='0' radius='.3'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b' boneName='Root'/>
                <edge id='bc' partId='p' from='b' to='c'/></edges>
                <parts><part id='p' locked='\(locked)'/></parts>
                <components><component id='cp' linkDataType='partId' linkData='p'/></components></canvas>
                """.utf8))
    }

    private func select(_ action: GraphSelectionAction, session: EditorSession) async throws -> EditorSnapshot {
        switch action {
        case .insertMidpoints, .reverseEdges: try await session.selectGraph(nodes: [], edges: ["ab"])
        case .reduceNodes, .deleteSelection: try await session.selectGraph(nodes: ["b"], edges: [])
        }
    }

    func testTitlesOrderAndDestructiveClassificationMatchExistingCommands() {
        XCTAssertEqual(
            GraphSelectionAction.allCases.map(\.title),
            [
                "Insert Midpoints on Selected Edges", "Reverse Selected Edges", "Reduce Selected Nodes",
                "Delete Graph Selection",
            ])
        XCTAssertEqual(GraphSelectionAction.allCases.filter(\.isDestructive), [.deleteSelection])
    }

    func testAvailabilityUsesExplicitEdgesNodesAndReadOnlyRules() throws {
        for locked in [false, true] {
            var state = try EditorState(document: document(locked: locked))
            for action in GraphSelectionAction.allCases {
                XCTAssertFalse(GraphSelectionActionTarget(snapshot: state.snapshot, action: action).isAvailable)
            }
            try state.selectEdge("ab")
            for action in GraphSelectionAction.allCases {
                XCTAssertEqual(
                    GraphSelectionActionTarget(snapshot: state.snapshot, action: action).isAvailable,
                    !locked && action != .reduceNodes)
            }
            try state.select("b")
            for action in GraphSelectionAction.allCases {
                XCTAssertEqual(
                    GraphSelectionActionTarget(snapshot: state.snapshot, action: action).isAvailable,
                    !locked && (action == .reduceNodes || action == .deleteSelection))
            }
            try state.select("a")
            XCTAssertFalse(GraphSelectionActionTarget(snapshot: state.snapshot, action: .reduceNodes).isAvailable)
        }
    }

    func testEachDelegatePreservesOneExactUndoRedoAndItsGraphSemantics() async throws {
        for action in GraphSelectionAction.allCases {
            let original = try document()
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await select(action, session: session)
            let target = GraphSelectionActionTarget(snapshot: selected, action: action)
            XCTAssertEqual(target.action, action)
            XCTAssertTrue(target.isAvailable)
            XCTAssertTrue(target.isCurrent(in: selected))
            let result = try await session.performGraphSelectionAction(target: target)
            XCTAssertEqual(result.documentRevision, selected.documentRevision + 1)
            XCTAssertFalse(target.isCurrent(in: result))
            switch action {
            case .insertMidpoints:
                XCTAssertEqual(result.nodes.count, 4)
                XCTAssertEqual(result.edges.count, 3)
                let inserted = try XCTUnwrap(result.nodes.first { !["a", "b", "c"].contains($0.id) })
                XCTAssertEqual(inserted.value.position.x, 0.25)
                XCTAssertEqual(inserted.value.radius, 0.15, accuracy: 0.000001)
                XCTAssertEqual(result.edges.filter { $0.boneName == "Root" }.count, 2)
            case .reverseEdges:
                XCTAssertEqual(result.nodes.count, 3)
                XCTAssertEqual(result.edges.count, 2)
                let edge = try XCTUnwrap(result.edges.first { $0.id == "ab" })
                XCTAssertEqual(edge.fromID, "b")
                XCTAssertEqual(edge.toID, "a")
                XCTAssertEqual(edge.boneName, "Root")
            case .reduceNodes:
                XCTAssertEqual(Set(result.nodes.map(\.id)), ["a", "c"])
                XCTAssertEqual(result.edges.count, 1)
            case .deleteSelection:
                XCTAssertEqual(Set(result.nodes.map(\.id)), ["a", "c"])
                XCTAssertTrue(result.edges.isEmpty)
                XCTAssertEqual(result.parts.count, 2)
            }
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), original.encoded())
            XCTAssertFalse(undone.canUndo)
            let redone = try await session.redo()
            XCTAssertEqual(redone.document.encoded(), result.document.encoded())
        }
    }

    func testInitiallyUnavailableActionNeverAcquiresLaterIntent() async throws {
        let session = EditorSession()
        let original = try document()
        let empty = try await session.open(data: original.encoded())
        let target = GraphSelectionActionTarget(snapshot: empty, action: .insertMidpoints)
        do {
            _ = try await session.performGraphSelectionAction(target: target)
            XCTFail("Expected unavailable action")
        } catch { XCTAssertEqual(error as? GraphSelectionActionError, .unavailable) }
        let selected = try await session.selectEdge("ab")
        XCTAssertFalse(target.isCurrent(in: selected))
        do {
            _ = try await session.performGraphSelectionAction(target: target)
            XCTFail("Unavailable target acquired a later selection")
        } catch { XCTAssertEqual(error as? GraphSelectionActionError, .staleTarget) }
        let after = try await session.selectEdge("ab")
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertFalse(after.canUndo)
    }

    func testSelectionConstraintUndoReplacementAndOtherWindowRejectRetainedTargets() async throws {
        for action in GraphSelectionAction.allCases {
            for mode in 0..<5 {
                let original = try document()
                let session = EditorSession()
                _ = try await session.open(data: original.encoded())
                let selected = try await select(action, session: session)
                let target = GraphSelectionActionTarget(snapshot: selected, action: action)
                let current: EditorSnapshot
                let recipient: EditorSession
                switch mode {
                case 0:
                    _ = try await session.select("a")
                    current = try await select(action, session: session)
                    recipient = session
                case 1:
                    _ = try await session.setLock(.x, isLocked: true)
                    current = try await session.setLock(.x, isLocked: false)
                    recipient = session
                case 2:
                    _ = try await session.apply([.setPartName(id: "p", name: "Changed")])
                    current = try await session.undo()
                    recipient = session
                case 3:
                    _ = try await session.open(data: original.encoded())
                    current = try await select(action, session: session)
                    recipient = session
                default:
                    let other = EditorSession()
                    _ = try await other.open(data: original.encoded())
                    current = try await select(action, session: other)
                    recipient = other
                }
                XCTAssertFalse(target.isCurrent(in: current))
                do {
                    _ = try await recipient.performGraphSelectionAction(target: target)
                    XCTFail("Expected stale target")
                } catch {
                    XCTAssertEqual(error as? GraphSelectionActionError, .staleTarget)
                    XCTAssertFalse(error.localizedDescription.isEmpty)
                }
                let after = try await select(action, session: recipient)
                XCTAssertEqual(after.document.encoded(), current.document.encoded())
                XCTAssertEqual(after.documentRevision, current.documentRevision)
                XCTAssertEqual(after.canRedo, current.canRedo)
            }
        }
    }

    func testPrecancelledDispatchNeverPublishesAnEdit() async throws {
        for action in GraphSelectionAction.allCases {
            let session = EditorSession()
            let original = try document()
            _ = try await session.open(data: original.encoded())
            let selected = try await select(action, session: session)
            let target = GraphSelectionActionTarget(snapshot: selected, action: action)
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await session.performGraphSelectionAction(target: target)
            }
            do {
                _ = try await cancelled.value
                XCTFail("Expected cancellation")
            } catch { XCTAssertTrue(error is CancellationError) }
            let after = try await select(action, session: session)
            XCTAssertEqual(after.document.encoded(), original.encoded())
            XCTAssertEqual(after.documentRevision, selected.documentRevision)
            XCTAssertFalse(after.canUndo)
        }
    }

    func testDispatchRequiresAnOpenDocument() async throws {
        let snapshot = try EditorState(document: document()).snapshot
        let target = GraphSelectionActionTarget(snapshot: snapshot, action: .deleteSelection)
        do {
            _ = try await EditorSession().performGraphSelectionAction(target: target)
            XCTFail("Expected unloaded session")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
    }
}
