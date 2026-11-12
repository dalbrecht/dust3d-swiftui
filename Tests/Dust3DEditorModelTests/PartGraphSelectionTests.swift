import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class PartGraphSelectionTests: XCTestCase {
    private func document(partState: String = "", malformed: Bool = false) throws -> Dust3DDocument {
        let nodes = [("a", "p", 0), ("b", "p", 1), ("c", "p", 3), ("d", "p", 4), ("u", "q", 6), ("v", "q", 7)].map {
            "<node id='\($0.0)' partId='\($0.1)' x='\($0.2)' y='\($0.2 % 2)' z='\($0.2)' radius='0.1'/>"
        }.joined()
        let extra =
            malformed
            ? "<edge id='foreign' partId='q' from='a' to='b'/><edge id='unowned' from='a' to='b'/><edge id='unknown' partId='absent' from='c' to='d'/><edge id='emptyowner' partId='' from='u' to='v'/>"
            : ""
        return try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes>\(nodes)<node id='orphan' x='9' y='0' z='9' radius='0.1'/></nodes><edges><edge id='ab' partId='p' from='a' to='b' boneName='Root'/><edge id='cd' partId='p' from='c' to='d'/><edge id='uv' partId='q' from='u' to='v'/>\(extra)</edges><parts><part id='p' \(partState)/><part id='q'/></parts><components><component id='root'><component id='group'><component id='leafp' linkData='p' linkDataType='partId'/></component><component id='leafq' linkData='q' linkDataType='partId'/></component></components></canvas>"
                    .utf8))
    }

    func testRevealLookupUsesUniqueExactOwnersAndRejectsStaleSnapshots() throws {
        let source = try document(malformed: true)
        let xml = String(decoding: source.modelXML, as: UTF8.self)
            .replacingOccurrences(
                of: "</components>", with: "<component id='duplicate' linkData='q' linkDataType='partId'/></components>"
            )
        var state = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        let lookup = GraphComponentRevealLookup(snapshot: state.snapshot)
        XCTAssertTrue(lookup.contains(.node("a"), in: state.snapshot))
        XCTAssertTrue(lookup.contains(.edge("ab"), in: state.snapshot))
        XCTAssertFalse(lookup.contains(.node("u"), in: state.snapshot))
        XCTAssertFalse(lookup.contains(.edge("foreign"), in: state.snapshot))
        XCTAssertFalse(lookup.contains(.edge("unowned"), in: state.snapshot))
        XCTAssertFalse(lookup.contains(.node("orphan"), in: state.snapshot))

        try state.select("a")
        XCTAssertTrue(lookup.contains(.node("a"), in: state.snapshot))
        try state.edit(id: "a", position: .init(x: 2, y: 0, z: 0), radius: 0.1)
        XCTAssertFalse(lookup.contains(.node("a"), in: state.snapshot))
        XCTAssertTrue(GraphComponentRevealLookup(snapshot: state.snapshot).contains(.node("a"), in: state.snapshot))
    }

    func testRevealOwningComponentPreservesGraphPicksAndHistory() async throws {
        let source = try document(malformed: true)
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.selectGraph(nodes: ["a"], edges: ["ab", "uv"])
        let context = PartGraphSelectionContext(snapshot: before)

        let node = try await session.revealOwningComponent(.node("c"), context: context)
        XCTAssertEqual(node.componentRevealHint?.componentID, "leafp")
        XCTAssertEqual(node.componentRevealHint?.ancestorIDs, ["root", "group"])

        // The edge's stored owner differs from the owner of both endpoints.
        let edge = try await session.revealOwningComponent(.edge("foreign"), context: context)
        XCTAssertEqual(edge.componentRevealHint?.componentID, "leafq")
        XCTAssertEqual(edge.componentRevealHint?.ancestorIDs, ["root"])
        XCTAssertEqual(edge.selectedIDs, before.selectedIDs)
        XCTAssertEqual(edge.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(edge.selectionRevision, before.selectionRevision)
        XCTAssertEqual(edge.documentRevision, before.documentRevision)
        XCTAssertEqual(edge.document.encoded(), before.document.encoded())
        XCTAssertEqual(edge.previewIdentity, before.previewIdentity)
        XCTAssertFalse(edge.canUndo)
    }

    func testSelectOwningComponentKeepsCanvasPicksAndRevealsTheExactStoredOwner() throws {
        let source = try document(malformed: true)
        var state = try EditorState(document: source)
        try state.selectGraph(nodes: ["a"], edges: ["ab"])
        let before = state.snapshot
        let context = PartGraphSelectionContext(snapshot: before)

        try state.revealOwningComponent(.node("c"), context: context, selecting: true)
        XCTAssertEqual(state.snapshot.selectedComponentIDs, ["leafp"])
        XCTAssertEqual(state.snapshot.componentRevealHint?.ancestorIDs, ["root", "group"])
        try state.revealOwningComponent(.edge("foreign"), context: context, selecting: true)
        let edge = state.snapshot
        XCTAssertEqual(edge.selectedComponentIDs, ["leafq"])
        XCTAssertEqual(edge.componentRevealHint?.componentID, "leafq")
        XCTAssertEqual(edge.selectedIDs, before.selectedIDs)
        XCTAssertEqual(edge.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(edge.document.encoded(), before.document.encoded())
        XCTAssertEqual(edge.previewIdentity, before.previewIdentity)
        XCTAssertFalse(edge.canUndo)

        XCTAssertThrowsError(try state.revealOwningComponent(.edge("unowned"), context: context, selecting: true)) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponent)
        }
        XCTAssertEqual(state.snapshot.selectedComponentIDs, edge.selectedComponentIDs)
        XCTAssertEqual(state.snapshot.componentRevealHint, edge.componentRevealHint)
    }

    func testHoveredOwnerSelectionKeepsComponentAndCanvasEditsScoped() async throws {
        let source = try document(malformed: true)
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        let selected = try await session.revealOwningComponent(
            .edge("foreign"), context: PartGraphSelectionContext(snapshot: before), selecting: true)
        let componentID = try XCTUnwrap(selected.selectedComponentID)
        let color = DocumentColor(red: 10, green: 20, blue: 30, alpha: 255)
        let colored = try await session.apply([.setComponentColor(id: componentID, color: color)])
        XCTAssertEqual(colored.selectedComponentIDs, ["leafq"])
        XCTAssertEqual(colored.selectedIDs, ["a"])
        XCTAssertEqual(colored.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(colored.componentTree.rows.first { $0.id == "leafq" }?.component.color, .value(color))
        XCTAssertEqual(colored.componentTree.rows.first { $0.id == "leafp" }?.component.color, .unset)

        let transformed = try await session.transformSelection(.flipX)
        XCTAssertEqual(try transformed.document.node(id: "a").position.x, 1)
        XCTAssertEqual(try transformed.document.node(id: "b").position.x, 0)
        XCTAssertEqual(try transformed.document.node(id: "u").position.x, 6)
        XCTAssertEqual(transformed.selectedComponentIDs, ["leafq"])
        let undoTransform = try await session.undo()
        XCTAssertEqual(undoTransform.document.encoded(), colored.document.encoded())
        let undoColor = try await session.undo()
        XCTAssertEqual(undoColor.document.encoded(), source.encoded())
        XCTAssertFalse(undoColor.canUndo)
    }

    func testRevealOwningComponentRejectsStaleOrUnresolvedTargets() throws {
        let source = try document(malformed: true)
        var state = try EditorState(document: source)
        let context = PartGraphSelectionContext(snapshot: state.snapshot)
        XCTAssertTrue(state.snapshot.canRevealOwningComponent(.node("a")))
        XCTAssertFalse(state.snapshot.canRevealOwningComponent(.node("orphan")))
        XCTAssertFalse(state.snapshot.canRevealOwningComponent(.edge("unowned")))
        XCTAssertThrowsError(try state.revealOwningComponent(.edge("unowned"), context: context))
        XCTAssertNil(state.snapshot.componentRevealHint)
        try state.edit(id: "a", position: .init(x: 2, y: 0, z: 0), radius: 0.1)
        XCTAssertThrowsError(try state.revealOwningComponent(.node("a"), context: context)) {
            XCTAssertEqual($0 as? EditorError, .stalePartGraphSelection)
        }
        XCTAssertNil(state.snapshot.componentRevealHint)
    }

    func testComponentGraphUsesCapturedRowsAndRejectsStaleActivation() throws {
        let original = try document(partState: "locked='true'")
        var state = try EditorState(document: original)
        try state.selectComponent("group")
        let before = state.snapshot
        let target = ComponentGraphSelectionTarget(snapshot: before, componentIDs: ["root", "leafq"])
        XCTAssertTrue(before.canSelectComponentGraph(target))
        try state.selectComponentGraph(target)
        XCTAssertEqual(state.snapshot.selectedIDs, ["u", "v"])
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["uv"])
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertThrowsError(try state.selectComponentGraph(target))
    }

    func testComponentGraphWithOnlyIneligibleDescendantsLeavesSelectionUnchanged() throws {
        for attributes in ["locked='true'", "visible='false'", "disabled='true'"] {
            let original = try document(partState: attributes)
            var state = try EditorState(document: original)
            try state.selectComponent("group")
            let before = state.snapshot
            let target = ComponentGraphSelectionTarget(snapshot: before, componentIDs: ["group"])
            XCTAssertFalse(before.canSelectComponentGraph(target), attributes)
            try state.selectComponentGraph(target)
            XCTAssertEqual(state.snapshot.selectedComponentIDs, before.selectedComponentIDs, attributes)
            XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision, attributes)
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded(), attributes)
        }
    }

    func testComponentGraphRequiresEditableEndpointsAndStoredOwner() throws {
        for attributes in ["locked='true'", "visible='false'", "disabled='true'", ""] {
            let original = try document(partState: attributes, malformed: true)
            var state = try EditorState(document: original)
            let before = state.snapshot
            let target = ComponentGraphSelectionTarget(snapshot: before, componentIDs: ["leafq"])
            try state.selectComponentGraph(target)
            XCTAssertEqual(state.snapshot.selectedIDs, ["u", "v"], attributes)
            XCTAssertEqual(state.snapshot.selectedEdgeIDs, attributes.isEmpty ? ["uv", "foreign"] : ["uv"], attributes)
            XCTAssertTrue(state.snapshot.canEditSelectedEdges, attributes)
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded(), attributes)
            XCTAssertEqual(state.snapshot.documentRevision, before.documentRevision, attributes)
            XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity, attributes)
            XCTAssertFalse(state.snapshot.canUndo, attributes)
            try state.reverseExplicitlySelectedEdges()
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded(), attributes)
        }
    }

    func testWholePartSelectsDisconnectedOwnedNodesAndEdgesWithIndependentRevealAndOneEpoch() throws {
        let original = try document(malformed: true)
        var state = try EditorState(document: original)
        try state.selectComponent("root")
        let before = state.snapshot
        try state.selectWholePart(.part("p"))
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab", "cd"])
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        XCTAssertNil(state.snapshot.selectedPartID)
        XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision + 1)
        XCTAssertEqual(state.snapshot.componentRevealHint?.componentID, "leafp")
        XCTAssertEqual(state.snapshot.componentRevealHint?.ancestorIDs, ["root", "group"])
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity)
        XCTAssertEqual(state.snapshot.documentRevision, before.documentRevision)
        XCTAssertFalse(state.snapshot.canUndo)
        let selected = state.snapshot
        try state.selectWholePart(.node("c"))
        XCTAssertEqual(state.snapshot.selectionRevision, selected.selectionRevision)
        XCTAssertGreaterThan(
            try XCTUnwrap(state.snapshot.componentRevealHint).revision,
            try XCTUnwrap(selected.componentRevealHint).revision)
        try state.selectWholePart(.edge("foreign"))
        XCTAssertEqual(state.snapshot.selectedIDs, ["u", "v"])
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["uv", "foreign"])
        XCTAssertEqual(state.snapshot.componentRevealHint?.componentID, "leafq")
    }

    func testMissingOwnershipAndStaleTargetsRejectAtomicallyWithoutChangingReveal() throws {
        var state = try EditorState(document: document(malformed: true))
        try state.selectWholePart(.part("p"))
        let selected = state.snapshot
        for target: PartGraphTarget in [
            .part("absent"), .node("missing"), .edge("missing"), .node("orphan"), .edge("unowned"), .edge("unknown"),
            .edge("emptyowner"),
        ] {
            XCTAssertFalse(state.snapshot.canSelectWholePart(target))
            XCTAssertNil(state.snapshot.partID(for: target))
            XCTAssertThrowsError(try state.selectWholePart(target))
            XCTAssertEqual(state.snapshot.selectedIDs, selected.selectedIDs)
            XCTAssertEqual(state.snapshot.selectedEdgeIDs, selected.selectedEdgeIDs)
            XCTAssertEqual(state.snapshot.componentRevealHint, selected.componentRevealHint)
            XCTAssertEqual(state.snapshot.selectionRevision, selected.selectionRevision)
        }
        let context = PartGraphSelectionContext(snapshot: state.snapshot)
        try state.apply([.setPartName(id: "p", name: "Renamed")])
        let edited = state.snapshot
        XCTAssertFalse(context.isCurrent(in: edited))
        XCTAssertThrowsError(try state.selectWholePart(.part("q"), context: context)) {
            XCTAssertEqual($0 as? EditorError, .stalePartGraphSelection)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), edited.document.encoded())
        XCTAssertEqual(state.snapshot.selectedIDs, edited.selectedIDs)
        XCTAssertEqual(state.snapshot.selectionRevision, edited.selectionRevision)
    }

    func testReadonlyHiddenAndDisabledPartGraphRemainsInspectable() throws {
        for flag in ["locked='true'", "visible='false'", "disabled='true'"] {
            let original = try document(partState: flag)
            var state = try EditorState(document: original)
            XCTAssertTrue(state.snapshot.canSelectWholePart(.edge("ab")))
            try state.selectWholePart(.edge("ab"))
            XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
            XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab", "cd"])
            XCTAssertFalse(state.snapshot.canEditSelectedEdges)
            XCTAssertFalse(state.snapshot.canInsertSelectedEdgeMidpoints)
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testPartGraphImmediatelyEnablesExplicitEdgeBatchesAndInvalidatesPriorDrag() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.select("a")
        let projection = CanvasProjection(
            bounds: .init(nodes: state.snapshot.nodes), plane: .front, width: 600, height: 400)
        let drag = try NodeDrag(anchorID: "a", snapshot: state.snapshot, projection: projection)
        try state.selectWholePart(.node("a"))
        XCTAssertFalse(drag.isCurrent(in: state.snapshot))
        XCTAssertTrue(state.snapshot.canEditSelectedEdges)
        XCTAssertTrue(state.snapshot.canInsertSelectedEdgeMidpoints)
        try state.insertSelectedEdgeMidpoints(identities: [
            .init(originalEdgeID: "ab", nodeID: "mab", edgeID: "tab"),
            .init(originalEdgeID: "cd", nodeID: "mcd", edgeID: "tcd"),
        ])
        XCTAssertEqual(state.snapshot.nodes.count, 9)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        try state.reverseExplicitlySelectedEdges()
        XCTAssertEqual(state.snapshot.edges.first { $0.id == "ab" }?.fromID, "b")
        XCTAssertEqual(state.snapshot.edges.first { $0.id == "uv" }?.fromID, "u")
    }

    func testActualEdgeOwnerMetadataAndDefaultInitializerAreBackwardCompatible() throws {
        let contents = try document(malformed: true).editorContents()
        XCTAssertEqual(contents.edges.first { $0.id == "ab" }?.partID, "p")
        XCTAssertEqual(contents.edges.first { $0.id == "foreign" }?.partID, "q")
        XCTAssertNil(contents.edges.first { $0.id == "unowned" }?.partID)
        XCTAssertEqual(contents.edges.first { $0.id == "unknown" }?.partID, "absent")
        let legacy = DocumentEdge(id: "edge", fromID: "a", toID: "b", boneName: "Root")
        XCTAssertNil(legacy.partID)
        XCTAssertNotEqual(legacy, DocumentEdge(id: "edge", fromID: "a", toID: "b", boneName: "Root", partID: "p"))
    }
    func testTargetedSessionContextIsWindowSpecificButIndependentOfPriorSelection() async throws {
        let first = EditorSession()
        let second = EditorSession()
        let original = try document()
        let opened = try await first.open(data: original.encoded())
        _ = try await second.open(data: original.encoded())
        let context = PartGraphSelectionContext(snapshot: opened)
        _ = try await first.selectComponent("root")
        let selected = try await first.selectWholePart(.edge("ab"), context: context)
        XCTAssertTrue(context.isCurrent(in: selected))
        XCTAssertEqual(selected.selectedIDs, ["a", "b", "c", "d"])
        XCTAssertEqual(selected.selectedEdgeIDs, ["ab", "cd"])
        XCTAssertTrue(selected.selectedComponentIDs.isEmpty)
        _ = try await second.select("u")
        do {
            _ = try await second.selectWholePart(.part("p"), context: context)
            XCTFail("A different window must reject the queued target")
        } catch { XCTAssertEqual(error as? EditorError, .stalePartGraphSelection) }
        let untouched = try await second.moveSelection(by: .init(x: 0, y: 0, z: 0))
        XCTAssertEqual(untouched.selectedIDs, ["u"])
        XCTAssertTrue(untouched.selectedEdgeIDs.isEmpty)
        XCTAssertEqual(untouched.document.encoded(), original.encoded())
        XCTAssertFalse(untouched.canUndo)
    }

    func testRevealIsClearedByNormalSelectionAndDocumentEditsButRejectedInputsKeepIt() throws {
        var state = try EditorState(document: document())
        try state.selectWholePart(.part("p"))
        let hint = state.snapshot.componentRevealHint
        XCTAssertThrowsError(try state.selectGraph(nodes: ["missing"], edges: []))
        XCTAssertThrowsError(try state.selectPart("missing"))
        XCTAssertThrowsError(try state.selectComponent("missing"))
        XCTAssertEqual(state.snapshot.componentRevealHint, hint)
        try state.select("a")
        XCTAssertNil(state.snapshot.componentRevealHint)
        try state.selectWholePart(.part("p"))
        try state.selectPart("q")
        XCTAssertNil(state.snapshot.componentRevealHint)
        try state.selectWholePart(.part("p"))
        try state.selectComponent("root")
        XCTAssertNil(state.snapshot.componentRevealHint)
        try state.selectWholePart(.part("p"))
        state.selectAll()
        XCTAssertNil(state.snapshot.componentRevealHint)
        try state.selectWholePart(.part("p"))
        state.selectAllNodes()
        XCTAssertNil(state.snapshot.componentRevealHint)
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        try state.selectWholePart(.part("p"))
        try state.apply([.setPartName(id: "p", name: "Renamed")])
        XCTAssertNil(state.snapshot.componentRevealHint)
    }

    func testEmptyOrUnassociatedPartDoesNotGuessRevealAndOpaqueHierarchyRemainsInspectable() throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='empty'/></parts><components><component id='unrelated'/></components></canvas>"
                    .utf8))
        var state = try EditorState(document: original)
        try state.selectComponent("unrelated")
        let epoch = state.snapshot.selectionRevision
        try state.selectWholePart(.part("empty"))
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        XCTAssertNil(state.snapshot.componentRevealHint)
        XCTAssertEqual(state.snapshot.selectionRevision, epoch + 1)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        let xml = String(decoding: try document().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "</components>", with: "<component id='root'/></components>")
        let opaque = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        var inspecting = try EditorState(document: opaque)
        XCTAssertNotNil(inspecting.snapshot.componentTree.failureDescription)
        try inspecting.selectWholePart(.part("p"))
        XCTAssertEqual(inspecting.snapshot.selectedIDs, ["a", "b", "c", "d"])
        XCTAssertEqual(inspecting.snapshot.selectedEdgeIDs, ["ab", "cd"])
        XCTAssertNil(inspecting.snapshot.componentRevealHint)
        XCTAssertEqual(inspecting.snapshot.document.encoded(), opaque.encoded())
    }

    func testBothProjectionTargetsResolveStoredOwnerAndNodeOnlyConvenienceRemainsSeparate() throws {
        let original = try document()
        var state = try EditorState(document: original)
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(
                bounds: .init(nodes: state.snapshot.nodes), plane: plane, width: 600, height: 400)
            let a = try XCTUnwrap(state.snapshot.nodes.first { $0.id == "a" })
            let b = try XCTUnwrap(state.snapshot.nodes.first { $0.id == "b" })
            let first = projection.point(for: a.value.position)
            let second = projection.point(for: b.value.position)
            let midpoint = CanvasPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
            let edgeID = try XCTUnwrap(
                projection.edgeID(near: midpoint, nodes: state.snapshot.nodes, edges: state.snapshot.edges))
            XCTAssertEqual(state.snapshot.partID(for: .edge(edgeID)), "p")
            try state.selectWholePart(.edge(edgeID))
            XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab", "cd"])
            XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
        }
        try state.select(Set(state.snapshot.nodes.filter { $0.partID == "p" }.map(\.id)))
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertFalse(state.snapshot.canEditSelectedEdges)
        XCTAssertFalse(state.snapshot.canInsertSelectedEdgeMidpoints)
        XCTAssertNil(state.snapshot.componentRevealHint)
    }

    func testWholePartSelectionAndRepeatRevealPreserveRedoAndPreviewIdentity() throws {
        var state = try EditorState(document: document())
        try state.apply([.setPartName(id: "p", name: "Renamed")])
        try state.undo()
        let before = state.snapshot
        let context = PartGraphSelectionContext(snapshot: before)
        for _ in 0..<2 { try state.selectWholePart(.node("c"), context: context) }
        XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
        XCTAssertEqual(state.snapshot.documentRevision, before.documentRevision)
        XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity)
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertTrue(state.snapshot.canRedo)
        try state.redo()
        XCTAssertEqual(state.snapshot.parts.first { $0.id == "p" }?.name, "Renamed")
    }

    func testNodeOnlyPartSelectionUsesCapturedContextAndRetainsReadonlyInspection() async throws {
        let original = try document(partState: "locked='true'")
        let first = EditorSession()
        let replaced = EditorSession()
        let opened = try await first.open(data: original.encoded())
        let context = PartGraphSelectionContext(snapshot: opened)
        let selected = try await first.selectPartNodes("p", context: context)
        XCTAssertEqual(selected.selectedIDs, ["a", "b", "c", "d"])
        XCTAssertTrue(selected.selectedEdgeIDs.isEmpty)
        XCTAssertTrue(selected.selectedComponentIDs.isEmpty)
        XCTAssertNil(selected.selectedPartID)
        XCTAssertNil(selected.componentRevealHint)
        XCTAssertEqual(selected.selectionRevision, opened.selectionRevision + 1)
        XCTAssertEqual(selected.document.encoded(), original.encoded())
        XCTAssertEqual(selected.previewIdentity, opened.previewIdentity)
        XCTAssertFalse(selected.canUndo)
        _ = try await replaced.open(data: original.encoded())
        _ = try await replaced.select("u")
        do {
            _ = try await replaced.selectPartNodes("p", context: context)
            XCTFail("A retained callback cannot target a reused identity in another document")
        } catch { XCTAssertEqual(error as? EditorError, .stalePartGraphSelection) }
        let unchanged = try await replaced.moveSelection(by: .init(x: 0, y: 0, z: 0))
        XCTAssertEqual(unchanged.selectedIDs, ["u"])
        XCTAssertTrue(unchanged.selectedEdgeIDs.isEmpty)
        XCTAssertFalse(unchanged.canUndo)
    }

    func testNodeOnlyPartSelectionClearsRevealButMissingAndEditedTargetsRejectAtomically() throws {
        var state = try EditorState(document: document())
        try state.selectWholePart(.part("q"))
        let selected = state.snapshot
        XCTAssertThrowsError(try state.selectPartNodes("missing")) {
            XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
        }
        XCTAssertEqual(state.snapshot.selectedIDs, selected.selectedIDs)
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, selected.selectedEdgeIDs)
        XCTAssertEqual(state.snapshot.componentRevealHint, selected.componentRevealHint)
        XCTAssertEqual(state.snapshot.selectionRevision, selected.selectionRevision)
        let context = PartGraphSelectionContext(snapshot: state.snapshot)
        try state.apply([.setPartName(id: "p", name: "Renamed")])
        let edited = state.snapshot
        XCTAssertThrowsError(try state.selectPartNodes("p", context: context)) {
            XCTAssertEqual($0 as? EditorError, .stalePartGraphSelection)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), edited.document.encoded())
        XCTAssertEqual(state.snapshot.selectedIDs, edited.selectedIDs)
        try state.selectWholePart(.part("p"))
        let epoch = state.snapshot.selectionRevision
        try state.selectPartNodes("p")
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertNil(state.snapshot.componentRevealHint)
        XCTAssertEqual(state.snapshot.selectionRevision, epoch + 1)
        let nodesOnlyEpoch = state.snapshot.selectionRevision
        try state.selectPartNodes("p")
        XCTAssertEqual(state.snapshot.selectionRevision, nodesOnlyEpoch)
    }

}
