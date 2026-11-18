import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class NodeConnectionTests: XCTestCase {
    private func source(locked: Bool = false) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' name='A' partId='p' x='.1' y='.5' z='.5' radius='.1'/>
                <node id='b' name='B' partId='p' x='.2' y='.5' z='.5' radius='.1'/>
                <node id='c' name='C' partId='q' x='.8' y='.5' z='.5' radius='.1' future='keep'/>
                <node id='d' name='D' partId='q' x='.9' y='.5' z='.5' radius='.1'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='cd' partId='q' from='c' to='d'/></edges>
                <parts><part id='p' name='Left' deformWidth='1.2'/><part id='q' name='Right' deformWidth='.8' locked='\(locked)'/></parts>
                <components><component id='cp' linkDataType='partId' linkData='p' color='#ff112233'/><component id='cq' linkDataType='partId' linkData='q' color='#ff445566'/></components><future token='retained'/></canvas>
                """.utf8))
    }

    func testEachExplicitOwnerRetainsItsPartSettingsWithOneUndoRedoAndSelection() throws {
        for owner in ["a", "c"] {
            let original = try source()
            var state = try EditorState(document: original)
            try state.select(["a", "c"])
            let target = NodeConnectionTarget(snapshot: state.snapshot)
            XCTAssertEqual(target.owners.map(\.nodeID), ["a", "c"])
            XCTAssertTrue(target.requiresOwnershipChoice)
            try state.connectSelectedNodes(target: target, ownerID: owner, edgeID: "join")
            let joined = state.snapshot
            let part = owner == "a" ? "p" : "q"
            XCTAssertEqual(Set(joined.nodes.compactMap(\.partID)), [part])
            XCTAssertEqual(joined.parts.map(\.id), [part])
            XCTAssertEqual(joined.parts.first?.name, owner == "a" ? "Left" : "Right")
            XCTAssertEqual(joined.selectedIDs, ["a", "c"])
            XCTAssertEqual(joined.edges.count, 3)
            XCTAssertTrue(String(decoding: joined.document.modelXML, as: UTF8.self).contains("retained"))
            XCTAssertFalse(target.isCurrent(in: joined))
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
            try state.redo()
            XCTAssertEqual(state.snapshot.document.encoded(), joined.document.encoded())
        }
    }

    func testRevealedComponentKeepsSelectedEndpointsConnectable() throws {
        let original = try source()
        var state = try EditorState(document: original)
        try state.select(["a", "c"])
        let beforeReveal = NodeConnectionTarget(snapshot: state.snapshot)
        try state.revealOwningComponent(
            .node("d"), context: PartGraphSelectionContext(snapshot: state.snapshot), selecting: true)
        let revealed = state.snapshot
        XCTAssertEqual(revealed.selectedComponentIDs, ["cq"])
        XCTAssertFalse(beforeReveal.isCurrent(in: revealed))
        let target = NodeConnectionTarget(snapshot: revealed)
        XCTAssertEqual(target.owners.map(\.nodeID), ["a", "c"])
        try state.connectSelectedNodes(target: target, ownerID: "a", edgeID: "join")
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "c"])
        XCTAssertEqual(state.snapshot.edges.count, 3)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
    }

    func testSamePartUsesOneChoiceAndExistingJoinSemanticsCanCloseItsChain() throws {
        let original = try source().applying(.joinNodes(id: "first", from: "a", to: "c"))
        var state = try EditorState(document: original)
        try state.select(["b", "d"])
        let target = NodeConnectionTarget(snapshot: state.snapshot)
        XCTAssertEqual(target.owners.count, 2)
        XCTAssertFalse(target.requiresOwnershipChoice)
        try state.connectSelectedNodes(target: target, ownerID: "b", edgeID: "close")
        XCTAssertEqual(state.snapshot.edges.count, 4)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testSelectionConstraintDocumentUndoAndWindowChangesRejectRetainedTargetsAtomically() throws {
        for change in 0..<4 {
            let original = try source()
            var state = try EditorState(document: original)
            try state.select(["a", "c"])
            let target = NodeConnectionTarget(snapshot: state.snapshot)
            switch change {
            case 0:
                try state.select(["b", "d"])
                try state.select(["a", "c"])
            case 1:
                state.setLock(.x, isLocked: true)
                state.setLock(.x, isLocked: false)
            case 2:
                try state.apply([.setPartName(id: "p", name: "Changed")])
                try state.undo()
            default:
                state = try EditorState(document: original)
                try state.select(["a", "c"])
            }
            let before = state.snapshot
            XCTAssertThrowsError(try state.connectSelectedNodes(target: target, ownerID: "a", edgeID: "join")) {
                XCTAssertEqual($0 as? NodeConnectionSelectionError, .staleTarget)
                XCTAssertTrue($0.localizedDescription.contains("selection changed"))
            }
            XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
            XCTAssertEqual(state.snapshot.canRedo, before.canRedo)
            XCTAssertEqual(state.snapshot.documentRevision, before.documentRevision)
        }
    }

    func testWrongCardinalityMixedEdgesAdjacentAndReadonlySelectionsStayUnavailable() throws {
        for ids: Set<String> in [[], ["a"], ["a", "b"], ["a", "b", "c"]] {
            var state = try EditorState(document: source())
            try state.select(ids)
            XCTAssertTrue(NodeConnectionTarget(snapshot: state.snapshot).owners.isEmpty)
        }
        var state = try EditorState(document: source())
        try state.selectGraph(nodes: ["a", "c"], edges: ["ab"])
        XCTAssertTrue(NodeConnectionTarget(snapshot: state.snapshot).owners.isEmpty)
        var locked = try EditorState(document: source(locked: true))
        try locked.select(["a", "c"])
        XCTAssertTrue(NodeConnectionTarget(snapshot: locked.snapshot).owners.isEmpty)
    }

    func testInteriorUnassignedAndByteMismatchedPartReferencesStayUnavailable() throws {
        let original = try source()
        var xml = String(decoding: original.modelXML, as: UTF8.self)
        xml = xml.replacingOccurrences(
            of: "</nodes>", with: "<node id='e' partId='p' x='.3' y='.5' z='.5' radius='.1'/></nodes>"
        )
        .replacingOccurrences(of: "</edges>", with: "<edge id='be' partId='p' from='b' to='e'/></edges>")
        var interior = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        try interior.select(["b", "c"])
        XCTAssertTrue(NodeConnectionTarget(snapshot: interior.snapshot).owners.isEmpty)

        xml = String(decoding: original.modelXML, as: UTF8.self)
            .replacingOccurrences(
                of: "</nodes>", with: "<node id='unassigned' x='.3' y='.5' z='.5' radius='.1'/></nodes>")
        var unassigned = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        try unassigned.select(["unassigned", "c"])
        XCTAssertTrue(NodeConnectionTarget(snapshot: unassigned.snapshot).owners.isEmpty)

        xml = String(decoding: original.modelXML, as: UTF8.self)
        for quote in ["'", "\""] {
            xml = xml.replacingOccurrences(of: "id=\(quote)p\(quote)", with: "id=\(quote)cafe&#769;\(quote)")
                .replacingOccurrences(of: "partId=\(quote)p\(quote)", with: "partId=\(quote)caf&#233;\(quote)")
                .replacingOccurrences(of: "linkData=\(quote)p\(quote)", with: "linkData=\(quote)cafe&#769;\(quote)")
        }
        let aliasSource = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        var alias = try EditorState(document: aliasSource)
        try alias.select(["a", "c"])
        XCTAssertTrue(NodeConnectionTarget(snapshot: alias.snapshot).owners.isEmpty)
        XCTAssertEqual(alias.snapshot.document.encoded(), aliasSource.encoded())
        XCTAssertFalse(alias.snapshot.canUndo)
    }

    func testInvalidOwnerAndCapturedUnavailableTargetCannotAcquireLaterSelection() throws {
        let original = try source()
        var state = try EditorState(document: original)
        let empty = NodeConnectionTarget(snapshot: state.snapshot)
        try state.select(["a", "c"])
        let target = NodeConnectionTarget(snapshot: state.snapshot)
        for (intent, owner) in [(empty, "a"), (target, "missing")] {
            XCTAssertThrowsError(try state.connectSelectedNodes(target: intent, ownerID: owner, edgeID: "join")) {
                XCTAssertEqual($0 as? NodeConnectionSelectionError, .staleTarget)
                XCTAssertTrue($0.localizedDescription.contains("selection changed"))
            }
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testOwnerIdentityIsByteExactInsteadOfCanonicallyEquivalent() throws {
        var xml = String(decoding: try source().modelXML, as: UTF8.self)
        for quote in ["'", "\""] {
            xml = xml.replacingOccurrences(of: "id=\(quote)a\(quote)", with: "id=\(quote)cafe&#769;\(quote)")
                .replacingOccurrences(of: "from=\(quote)a\(quote)", with: "from=\(quote)cafe&#769;\(quote)")
        }
        XCTAssertTrue(xml.contains("cafe&#769;"))
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        var state = try EditorState(document: original)
        try state.select(["cafe\u{301}", "c"])
        let target = NodeConnectionTarget(snapshot: state.snapshot)
        XCTAssertEqual(target.owners.count, 2)
        XCTAssertEqual(target.owners.first?.id, Data("cafe\u{301}".utf8))
        XCTAssertThrowsError(try state.connectSelectedNodes(target: target, ownerID: "caf\u{e9}", edgeID: "join"))
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testOriginalJoinErrorsAndFullEdgeQuotaDoNotPublishOrEnable() throws {
        let original = try source()
        var state = try EditorState(document: original)
        try state.select(["a", "c"])
        let target = NodeConnectionTarget(snapshot: state.snapshot)
        let before = state.snapshot
        XCTAssertThrowsError(try state.connectSelectedNodes(target: target, ownerID: "a", edgeID: "ab")) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertEqual(state.snapshot.documentRevision, before.documentRevision)
        XCTAssertFalse(state.snapshot.canUndo)

        // Ordinary published graph cap: bounded metadata only, never preview/generator input.
        var xml = String(decoding: original.modelXML, as: UTF8.self)
        xml = xml.replacingOccurrences(
            of: "</nodes>",
            with:
                "<node id='x' partId='p' x='.3' y='.5' z='.5' radius='.1'/><node id='y' partId='q' x='.7' y='.5' z='.5' radius='.1'/></nodes>"
        )
        let extra = (0..<19_998).map { "<edge id='extra-\($0)' partId='p' from='a' to='b'/>" }.joined()
        xml = xml.replacingOccurrences(of: "</edges>", with: extra + "</edges>")
        var full = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        try full.select(["x", "y"])
        XCTAssertEqual(full.snapshot.edges.count, 20_000)
        XCTAssertTrue(NodeConnectionTarget(snapshot: full.snapshot).owners.isEmpty)
    }

    func testCancelledSessionRequestLeavesDocumentAndHistoryUntouched() async throws {
        let session = EditorSession()
        let original = try source()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.select(["a", "c"])
        let target = NodeConnectionTarget(snapshot: selected)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.connectSelectedNodes(target: target, ownerID: "a")
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled intent committed")
        } catch { XCTAssertTrue(error is CancellationError) }
        let after = try await session.select(["a", "c"])
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertFalse(after.canUndo)
    }

    func testSessionAllocatesOneEdgeAndPublishesOneUndoableJoin() async throws {
        let session = EditorSession()
        let original = try source()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.select(["a", "c"])
        let target = NodeConnectionTarget(snapshot: selected)
        let joined = try await session.connectSelectedNodes(target: target, ownerID: "c")
        XCTAssertEqual(joined.edges.count, 3)
        XCTAssertEqual(joined.documentRevision, selected.documentRevision + 1)
        XCTAssertEqual(Set(joined.nodes.compactMap(\.partID)), ["q"])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), joined.document.encoded())
    }
}
