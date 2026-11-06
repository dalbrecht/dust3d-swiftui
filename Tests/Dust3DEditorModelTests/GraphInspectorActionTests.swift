import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class GraphInspectorActionTests: XCTestCase {
    private func source(locked: Bool = false) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.3' y='.5' z='.5' radius='.1'/><node id='c' partId='p' x='.4' y='.5' z='.5' radius='.1'/><node id='x' partId='q' x='.8' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p' name='Owner' locked='\(locked)'/><part id='q' name='Consumed'/></parts><components><component id='cp' linkDataType='partId' linkData='p'/><component id='cq' linkDataType='partId' linkData='q'/></components><future value='keep'/></canvas>
                """.utf8))
    }

    func testEveryDocumentActionUsesOneExactUndoRedoTransaction() async throws {
        let cases: [(GraphInspectorAction, Set<String>, Set<String>, Int, Int)] = [
            (.connect(from: "a", to: "x"), ["a"], [], 4, 3),
            (.deleteNode(id: "b"), ["b"], [], 3, 0),
            (.reverseEdge(id: "ab"), ["a"], [], 4, 2),
            (.disconnectEdge(id: "ab"), [], ["ab"], 4, 1),
            (.insertMidpoint(edgeID: "ab"), [], ["ab"], 5, 3),
        ]
        for (action, nodes, edges, nodeCount, edgeCount) in cases {
            let original = try source()
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.selectGraph(nodes: nodes, edges: edges)
            let target = GraphInspectorActionContext(snapshot: selected).target(for: action)
            XCTAssertTrue(target.isCurrent(in: selected))
            XCTAssertTrue(target.changesDocument)
            let after = try await session.performInspectorAction(target: target)
            XCTAssertEqual(after.nodes.count, nodeCount)
            XCTAssertEqual(after.edges.count, edgeCount)
            XCTAssertEqual(after.documentRevision, selected.documentRevision + 1)
            XCTAssertFalse(target.isCurrent(in: after))
            XCTAssertTrue(String(decoding: after.document.modelXML, as: UTF8.self).contains("keep"))
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), original.encoded())
            XCTAssertFalse(undone.canUndo)
            let redone = try await session.redo()
            XCTAssertEqual(redone.document.encoded(), after.document.encoded())
        }
    }

    func testReadonlyEndpointSelectionStaysAvailableWithoutDocumentHistory() async throws {
        let session = EditorSession()
        let original = try source(locked: true)
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectGraph(nodes: [], edges: ["ab"])
        let context = GraphInspectorActionContext(snapshot: selected)
        XCTAssertFalse(context.target(for: .reverseEdge(id: "ab")).isCurrent(in: selected))
        XCTAssertFalse(context.target(for: .disconnectEdge(id: "ab")).isCurrent(in: selected))
        XCTAssertFalse(context.target(for: .insertMidpoint(edgeID: "ab")).isCurrent(in: selected))
        let target = context.target(for: .selectEndpoints(edgeID: "ab"))
        XCTAssertTrue(target.isCurrent(in: selected))
        XCTAssertFalse(target.changesDocument)
        let after = try await session.performInspectorAction(target: target)
        XCTAssertEqual(after.selectedIDs, ["a", "b"])
        XCTAssertTrue(after.selectedEdgeIDs.isEmpty)
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertEqual(after.documentRevision, selected.documentRevision)
        XCTAssertFalse(after.canUndo)
    }

    func testRetainedContextRejectsSelectionConstraintUndoReplacementAndOtherWindow() async throws {
        for change in 0..<5 {
            let original = try source()
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.select("a")
            let target = GraphInspectorActionContext(snapshot: selected).target(for: .deleteNode(id: "a"))
            switch change {
            case 0:
                _ = try await session.select("c")
                _ = try await session.select("a")
            case 1:
                _ = try await session.setLock(.x, isLocked: true)
                _ = try await session.setLock(.x, isLocked: false)
            case 2:
                _ = try await session.apply([.setPartName(id: "p", name: "Changed")])
                _ = try await session.undo()
            case 3:
                _ = try await session.open(data: original.encoded())
                _ = try await session.select("a")
            default:
                let other = EditorSession()
                _ = try await other.open(data: original.encoded())
                _ = try await other.select("a")
                do {
                    _ = try await other.performInspectorAction(target: target)
                    XCTFail("Other window")
                } catch { XCTAssertEqual(error as? GraphInspectorActionError, .staleTarget) }
                continue
            }
            let before = try await session.select("a")
            do {
                _ = try await session.performInspectorAction(target: target)
                XCTFail("Stale intent")
            } catch { XCTAssertEqual(error as? GraphInspectorActionError, .staleTarget) }
            let after = try await session.select("a")
            XCTAssertEqual(after.document.encoded(), before.document.encoded())
            XCTAssertEqual(after.documentRevision, before.documentRevision)
            XCTAssertEqual(after.canRedo, before.canRedo)
        }
    }

    func testUnrelatedInvalidAndInitiallyUnavailableActionsNeverAcquireContext() async throws {
        let session = EditorSession()
        let original = try source()
        let empty = try await session.open(data: original.encoded())
        let unavailable = GraphInspectorActionContext(snapshot: empty).target(for: .deleteNode(id: "a"))
        let selected = try await session.select("a")
        let context = GraphInspectorActionContext(snapshot: selected)
        let invalid: [GraphInspectorAction] = [
            .deleteNode(id: "b"), .connect(from: "c", to: "x"), .connect(from: "a", to: "b"),
            .reverseEdge(id: "bc"), .disconnectEdge(id: "missing"), .insertMidpoint(edgeID: "ab"),
            .selectEndpoints(edgeID: "ab"),
        ]
        for target in [unavailable] + invalid.map({ context.target(for: $0) }) {
            XCTAssertFalse(target.isCurrent(in: selected))
            do {
                _ = try await session.performInspectorAction(target: target)
                XCTFail("Unavailable")
            } catch { XCTAssertEqual(error as? GraphInspectorActionError, .staleTarget) }
        }
        let after = try await session.select("a")
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertFalse(after.canUndo)
        XCTAssertTrue(context.target(for: .reverseEdge(id: "ab")).isCurrent(in: selected))
    }

    func testByteExactNodeIdentityAndUnsupportedPartAliasesCannotEnableMutation() throws {
        let original = try source()
        var xml = String(decoding: original.modelXML, as: UTF8.self)
        for quote in ["'", "\""] {
            xml = xml.replacingOccurrences(of: "id=\(quote)a\(quote)", with: "id=\(quote)cafe&#769;\(quote)")
                .replacingOccurrences(of: "from=\(quote)a\(quote)", with: "from=\(quote)cafe&#769;\(quote)")
        }
        var state = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        try state.select("cafe\u{301}")
        let context = GraphInspectorActionContext(snapshot: state.snapshot)
        XCTAssertTrue(context.target(for: .deleteNode(id: "cafe\u{301}")).isCurrent(in: state.snapshot))
        XCTAssertFalse(context.target(for: .deleteNode(id: "caf\u{e9}")).isCurrent(in: state.snapshot))
        XCTAssertFalse(context.target(for: .connect(from: "caf\u{e9}", to: "x")).isCurrent(in: state.snapshot))

        xml = String(decoding: original.modelXML, as: UTF8.self)
        for quote in ["'", "\""] {
            xml = xml.replacingOccurrences(of: "id=\(quote)p\(quote)", with: "id=\(quote)cafe&#769;\(quote)")
                .replacingOccurrences(of: "partId=\(quote)p\(quote)", with: "partId=\(quote)caf&#233;\(quote)")
                .replacingOccurrences(of: "linkData=\(quote)p\(quote)", with: "linkData=\(quote)cafe&#769;\(quote)")
        }
        var alias = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        try alias.selectGraph(nodes: [], edges: ["ab"])
        let unsupported = GraphInspectorActionContext(snapshot: alias.snapshot)
        for action: GraphInspectorAction in [
            .reverseEdge(id: "ab"), .disconnectEdge(id: "ab"), .insertMidpoint(edgeID: "ab"),
        ] {
            XCTAssertFalse(unsupported.target(for: action).isCurrent(in: alias.snapshot))
        }
        XCTAssertTrue(unsupported.target(for: .selectEndpoints(edgeID: "ab")).isCurrent(in: alias.snapshot))
    }

    func testOriginalJoinFailurePreservesItsCauseSourceAndHistory() async throws {
        let xml = String(decoding: try source().modelXML, as: UTF8.self)
            .replacingOccurrences(
                of: "</nodes>", with: "<node id='y' partId='q' x='.9' y='.5' z='.5' radius='.1'/></nodes>")
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.select("a")
        let target = GraphInspectorActionContext(snapshot: selected).target(for: .connect(from: "a", to: "x"))
        XCTAssertTrue(target.isCurrent(in: selected))
        do {
            _ = try await session.performInspectorAction(target: target)
            XCTFail("Disconnected legacy target chain")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let after = try await session.select("a")
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertEqual(after.documentRevision, selected.documentRevision)
        XCTAssertFalse(after.canUndo)
    }

    func testCancelledActionPublishesNeitherDocumentNorSelection() async throws {
        let session = EditorSession()
        let original = try source()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectGraph(nodes: [], edges: ["ab"])
        let target = GraphInspectorActionContext(snapshot: selected).target(for: .disconnectEdge(id: "ab"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.performInspectorAction(target: target)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled action")
        } catch { XCTAssertTrue(error is CancellationError) }
        let after = try await session.selectGraph(nodes: [], edges: ["ab"])
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertFalse(after.canUndo)
    }
}
