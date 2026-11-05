import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class MixedGraphSelectionTests: XCTestCase {
    private func chain() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ["a", "b", "c", "d"].enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: "p", componentID: index == 0 ? "component" : nil,
                    position: .init(x: Double(index), y: Double(index + 1), z: Double(index + 2)), radius: 0.1))
        }
        for (id, from, to) in [("ab", "a", "b"), ("bc", "b", "c"), ("cd", "c", "d")] {
            document = try document.applying(.addEdge(id: id, from: from, to: to))
        }
        return document
    }

    func testEdgeOnlyDeletionCapturesOneOrderedBatchCommand() throws {
        var state = try EditorState(document: chain())
        try state.selectEdges(["cd", "ab"])
        let commands = try state.selectionDeletionCommands()
        XCTAssertEqual(commands.count, 1)
        guard let first = commands.first, case .removeEdges(let ids) = first else {
            return XCTFail("Bulk Delete must capture one edge batch, not one document mutation per edge")
        }
        XCTAssertEqual(ids, ["ab", "cd"])
    }

    func testAtomicMixedSelectionAddToggleReplacementAndLegacySingleAccessor() throws {
        var state = try EditorState(document: chain())
        let original = state.snapshot.document.encoded()
        try state.selectGraph(nodes: ["a"], edges: ["bc"])
        XCTAssertEqual(state.snapshot.selectedIDs, ["a"])
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["bc"])
        XCTAssertEqual(state.snapshot.selectedEdgeID, "bc")
        let revision = state.snapshot.selectionRevision
        try state.addToSelection(nodes: ["b"], edges: ["ab", "bc"])
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b"])
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab", "bc"])
        XCTAssertNil(state.snapshot.selectedEdgeID)
        XCTAssertGreaterThan(state.snapshot.selectionRevision, revision)
        let valid = state.snapshot
        XCTAssertThrowsError(try state.selectGraph(nodes: ["missing"], edges: ["cd"]))
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, valid.selectedEdgeIDs)
        XCTAssertEqual(state.snapshot.selectionRevision, valid.selectionRevision)
        try state.toggleSelection("a")
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab", "bc"])
        try state.toggleEdgeSelection("ab")
        XCTAssertEqual(state.snapshot.selectedIDs, ["b"])
        XCTAssertEqual(state.snapshot.selectedEdgeID, "bc")
        try state.selectComponent("component")
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        try state.selectEdges(["ab", "bc"])
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        try state.select("d")
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertEqual(state.snapshot.document.encoded(), original)
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testExplicitSubsetReverseDoesNotInferOtherEdgesAndBatchMidpointRetainsOriginalSelection() throws {
        let original = try chain()
        var state = try EditorState(document: original)
        try state.selectGraph(nodes: ["a", "b", "c"], edges: ["cd", "ab"])
        try state.reverseExplicitlySelectedEdges()
        XCTAssertEqual(state.snapshot.edges.first(where: { $0.id == "bc" })?.fromID, "b")
        XCTAssertEqual(state.snapshot.edges.first(where: { $0.id == "ab" })?.fromID, "b")
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        try state.insertSelectedEdgeMidpoints(identities: [
            .init(originalEdgeID: "cd", nodeID: "midcd", edgeID: "tailcd"),
            .init(originalEdgeID: "ab", nodeID: "midab", edgeID: "tailab"),
        ])
        XCTAssertEqual(state.snapshot.nodes.count, 6)
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["cd", "ab"])
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c"])
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testTransformUnionDeduplicatesEndpointsButExchangeAndCopyUseExplicitNodes() async throws {
        let session = EditorSession()
        let original = try chain()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectGraph(nodes: ["b"], edges: ["ab", "bc"])
        let moved = try await session.moveSelection(by: .init(x: 1, y: 0, z: 0))
        for node in moved.nodes {
            let baseline = try XCTUnwrap(original.editorContents().nodes.first(where: { $0.id == node.id }))
            XCTAssertEqual(node.value.position.x, baseline.value.position.x + (node.id == "d" ? 0 : 1))
        }
        let fragment = try await session.copySelection()
        XCTAssertEqual(fragment.selectedNodeIDs, ["b"])
        XCTAssertTrue(try fragment.document.editorContents().edges.isEmpty)
        _ = try await session.undo()
        let exchanged = try await session.transformSelection(.exchangeXZ)
        XCTAssertEqual(exchanged.nodes.first(where: { $0.id == "a" })?.value, try original.node(id: "a"))
        XCTAssertEqual(exchanged.nodes.first(where: { $0.id == "b" })?.value.position.x, 3)
    }

    func testEdgeEndpointDragParticipantsAndAllEdgeChangesInvalidateGesture() throws {
        var state = try EditorState(document: chain())
        try state.selectGraph(nodes: ["d"], edges: ["ab"])
        let drag = try NodeDrag(
            anchorID: "a", snapshot: state.snapshot,
            projection: .init(bounds: .init(nodes: state.snapshot.nodes), plane: .front, width: 500, height: 500))
        XCTAssertTrue(drag.includes("a"))
        XCTAssertTrue(drag.includes("b"))
        XCTAssertTrue(drag.includes("d"))
        XCTAssertFalse(drag.includes("c"))
        try state.addToSelection(nodes: [], edges: ["bc"])
        XCTAssertFalse(drag.isCurrent(in: state.snapshot))
        try state.toggleEdgeSelection("bc")
        XCTAssertFalse(drag.isCurrent(in: state.snapshot))
    }
    func testSelectAllGraphAndNodeOnlyConvenienceHaveIndependentExplicitSets() throws {
        var state = try EditorState(document: chain())
        state.selectAll()
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab", "bc", "cd"])
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
        let revision = state.snapshot.selectionRevision
        state.selectAllNodes()
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
        XCTAssertGreaterThan(state.snapshot.selectionRevision, revision)
    }

    func testEdgeOnlyDragCommitPreservesPicksAndMovesEachEndpointOnce() async throws {
        let session = EditorSession()
        _ = try await session.open(data: chain().encoded())
        let selected = try await session.selectEdges(["ab", "bc"])
        let projection = CanvasProjection(bounds: .init(nodes: selected.nodes), plane: .front, width: 500, height: 500)
        let drag = try NodeDrag(anchorID: "b", snapshot: selected, projection: projection)
        let moved = try await session.commitNodeDrag(drag, translation: .init(x: 10, y: 0))
        XCTAssertTrue(moved.selectedIDs.isEmpty)
        XCTAssertEqual(moved.selectedEdgeIDs, ["ab", "bc"])
        for id in ["a", "b", "c"] {
            let before = try XCTUnwrap(selected.nodes.first { $0.id == id })
            let after = try XCTUnwrap(moved.nodes.first { $0.id == id })
            let expected = drag.position(of: before.value.position, by: .init(x: 10, y: 0))
            XCTAssertEqual(after.value.position.x, expected.x, accuracy: 1e-12)
            XCTAssertEqual(after.value.position.y, expected.y, accuracy: 1e-12)
            XCTAssertEqual(after.value.position.z, expected.z, accuracy: 1e-12)
        }
        XCTAssertEqual(moved.nodes.first { $0.id == "d" }?.value, selected.nodes.first { $0.id == "d" }?.value)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), selected.document.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testMixedDeleteNormalizesCombinedRemovalOnceAndPrunesBothSets() async throws {
        let session = EditorSession()
        let original = try chain()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectGraph(nodes: ["b"], edges: ["ab", "cd"])
        let deleted = try await session.deleteSelection()
        XCTAssertEqual(Set(deleted.nodes.map(\.id)), ["a", "c", "d"])
        XCTAssertTrue(deleted.edges.isEmpty)
        XCTAssertTrue(deleted.selectedIDs.isEmpty)
        XCTAssertTrue(deleted.selectedEdgeIDs.isEmpty)
        XCTAssertGreaterThan(deleted.selectionRevision, selected.selectionRevision)
        XCTAssertEqual(Set(deleted.nodes.compactMap(\.partID)).count, 3)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        XCTAssertTrue(undone.selectedEdgeIDs.isEmpty)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), deleted.document.encoded())
    }

    func testMidpointBatchAllocatesInUUIDOrderAndFailureIsAtomic() throws {
        var state = try EditorState(document: chain())
        try state.selectEdges(["cd", "ab"])
        let original = state.snapshot
        XCTAssertThrowsError(
            try state.insertSelectedEdgeMidpoints(identities: [
                .init(originalEdgeID: "cd", nodeID: "collision", edgeID: "tailcd"),
                .init(originalEdgeID: "ab", nodeID: "collision", edgeID: "tailab"),
            ]))
        XCTAssertEqual(state.snapshot.document.encoded(), original.document.encoded())
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, original.selectedEdgeIDs)
        XCTAssertFalse(state.snapshot.canUndo)
        try state.insertSelectedEdgeMidpoints(identities: [
            .init(originalEdgeID: "cd", nodeID: "midcd", edgeID: "tailcd"),
            .init(originalEdgeID: "ab", nodeID: "midab", edgeID: "tailab"),
        ])
        XCTAssertEqual(Array(state.snapshot.nodes.suffix(2).map(\.id)), ["midab", "midcd"])
    }

    func testEdgeOnlyCopyIsUnavailableAndReductionOnlyConsumesExplicitNodes() async throws {
        let session = EditorSession()
        _ = try await session.open(data: chain().encoded())
        let selected = try await session.selectEdges(["ab", "bc"])
        XCTAssertFalse(selected.canCopyNodes)
        XCTAssertFalse(selected.canCutNodes)
        do {
            _ = try await session.copySelection()
            XCTFail("Edge-only copy must reject")
        } catch {}
        let unchanged = try await session.reduceSelectedNodes()
        XCTAssertEqual(unchanged.document.encoded(), selected.document.encoded())
        XCTAssertFalse(unchanged.canUndo)
        _ = try await session.addToSelection(nodes: ["b"], edges: [])
        let reduced = try await session.reduceSelectedNodes()
        XCTAssertEqual(Set(reduced.nodes.map(\.id)), ["a", "c", "d"])
        XCTAssertEqual(reduced.selectedEdgeIDs, ["ab"])
    }

    func testMarqueeCrossingTouchingAndCollapsedSegmentsAreExplicitInBothPlanes() throws {
        let document = try chain()
        let contents = try document.editorContents()
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(
                bounds: .init(nodes: contents.nodes), plane: plane, width: 500, height: 500)
            let first = projection.point(for: contents.nodes[1].value.position)
            let second = projection.point(for: contents.nodes[2].value.position)
            let center = CanvasPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
            let rectangle = CanvasSelectionRectangle(
                from: .init(x: center.x - 1, y: center.y - 1), to: .init(x: center.x + 1, y: center.y + 1))
            XCTAssertTrue(projection.nodeIDs(in: rectangle, nodes: contents.nodes).isEmpty)
            XCTAssertEqual(projection.edgeIDs(in: rectangle, nodes: contents.nodes, edges: contents.edges), ["bc"])
            let point = CanvasSelectionRectangle(from: first, to: first)
            XCTAssertEqual(projection.edgeIDs(in: point, nodes: contents.nodes, edges: contents.edges), ["ab", "bc"])
        }
    }

    func testUnionRadiusScalingAndTransformApplyOncePerNode() throws {
        var state = try EditorState(document: chain())
        try state.selectGraph(nodes: ["a", "b"], edges: ["ab", "bc"])
        try state.scaleSelection(positionFactor: 1, radiusFactor: 2)
        for node in state.snapshot.nodes {
            XCTAssertEqual(node.value.radius, node.id == "d" ? 0.1 : 0.2)
        }
        try state.undo()
        try state.selectEdges(["ab", "bc"])
        try state.transformSelection(.frontAlignX)
        for node in state.snapshot.nodes {
            XCTAssertEqual(node.value.position.x, node.id == "d" ? 3 : 1)
        }
    }

    func testReadonlyMixedPicksRemainInspectableAndCutPreflightsBeforeProducingPayload() async throws {
        let locked = try chain().applying(.setPartState(id: "p", property: .locked, value: true))
        let session = EditorSession()
        _ = try await session.open(data: locked.encoded())
        let selected = try await session.selectGraph(nodes: ["a"], edges: ["bc", "cd"])
        XCTAssertEqual(selected.selectedEdges.count, 2)
        XCTAssertTrue(selected.canCopyNodes)
        XCTAssertFalse(selected.canCutNodes)
        XCTAssertFalse(selected.canDeleteSelection)
        XCTAssertFalse(selected.canEditSelectedEdges)
        XCTAssertFalse(selected.canInsertSelectedEdgeMidpoints)
        do {
            _ = try await session.copyRepresentations(identifier: "cut", onlyEditable: true)
            XCTFail("readonly Cut must reject")
        } catch {}
        do {
            _ = try await session.reverseExplicitlySelectedEdges()
            XCTFail("readonly reverse must reject")
        } catch {}
        let unchanged = try await session.moveSelection(by: .init(x: 1, y: 0, z: 0))
        XCTAssertEqual(unchanged.document.encoded(), locked.encoded())
        XCTAssertEqual(unchanged.selectedEdgeIDs, ["bc", "cd"])
        XCTAssertFalse(unchanged.canUndo)
    }

    func testMarqueeUsesSelectedNativeStrokeWidthAndReadonlyVisibleInspection() throws {
        let source = try chain()
        for document in [source, try source.applying(.setPartState(id: "p", property: .locked, value: true))] {
            let contents = try document.editorContents()
            for plane in EditingPlane.allCases {
                let projection = CanvasProjection(
                    bounds: .init(nodes: contents.nodes), plane: plane, width: 500, height: 500)
                let from = projection.point(for: contents.nodes[1].value.position)
                let to = projection.point(for: contents.nodes[2].value.position)
                let dx = to.x - from.x
                let dy = to.y - from.y
                let length = (dx * dx + dy * dy).squareRoot()
                let point = CanvasPoint(
                    x: (from.x + to.x) / 2 - dy / length * 1.5, y: (from.y + to.y) / 2 + dx / length * 1.5)
                let rectangle = CanvasSelectionRectangle(from: point, to: point)
                XCTAssertTrue(projection.edgeIDs(in: rectangle, nodes: contents.nodes, edges: contents.edges).isEmpty)
                XCTAssertEqual(
                    projection.edgeIDs(
                        in: rectangle, nodes: contents.nodes, edges: contents.edges, selectedEdgeIDs: ["bc"]), ["bc"])
            }
        }
    }

    func testMixedSessionSelectionsAreIndependentAcrossWindows() async throws {
        let first = EditorSession()
        let second = EditorSession()
        let document = try chain()
        _ = try await first.open(data: document.encoded())
        _ = try await second.open(data: document.encoded())
        _ = try await first.selectGraph(nodes: ["a"], edges: ["ab", "cd"])
        let other = try await second.selectEdges(["bc"])
        XCTAssertTrue(other.selectedIDs.isEmpty)
        XCTAssertEqual(other.selectedEdgeIDs, ["bc"])
        let unchanged = try await first.moveSelection(by: .init(x: 0, y: 0, z: 0))
        XCTAssertEqual(unchanged.selectedIDs, ["a"])
        XCTAssertEqual(unchanged.selectedEdgeIDs, ["ab", "cd"])
    }

    func testNodeOnlyDeleteEligibilityReflectsEditableSelectionAndRetainsReadonlyInspection() throws {
        let original = try chain()
        var state = try EditorState(document: original)
        XCTAssertFalse(state.snapshot.canDeleteSelection)
        try state.select("b")
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertTrue(state.snapshot.canDeleteSelection)
        try state.deleteSelection()
        XCTAssertFalse(state.snapshot.nodes.contains { $0.id == "b" })
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        var readonly = try EditorState(
            document: original.applying(.setPartState(id: "p", property: .locked, value: true)))
        try readonly.select("b")
        XCTAssertFalse(readonly.snapshot.canDeleteSelection)
        let inspected = readonly.snapshot
        try readonly.deleteSelection()
        XCTAssertEqual(readonly.snapshot.document.encoded(), inspected.document.encoded())
        XCTAssertEqual(readonly.snapshot.selectedIDs, ["b"])
        XCTAssertFalse(readonly.snapshot.canUndo)
    }

    func testSelectAllNodesClearsEmptyGraphPartAndComponentContextsInOneEpoch() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='p'/></parts><components><component id='component' linkData='p' linkDataType='partId'/></components></canvas>"
                    .utf8))
        var state = try EditorState(document: document)
        try state.selectPart("p")
        var epoch = state.snapshot.selectionRevision
        state.selectAllNodes()
        XCTAssertNil(state.snapshot.selectedPartID)
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertEqual(state.snapshot.selectionRevision, epoch + 1)
        state.selectAllNodes()
        XCTAssertEqual(state.snapshot.selectionRevision, epoch + 1)
        try state.selectComponent("component")
        epoch = state.snapshot.selectionRevision
        state.selectAllNodes()
        XCTAssertTrue(state.snapshot.selectedComponentIDs.isEmpty)
        XCTAssertEqual(state.snapshot.selectionRevision, epoch + 1)
        XCTAssertEqual(state.snapshot.document.encoded(), document.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testMidpointBatchRejectsWrongCapturedSetAndReadonlyDirectCallsWithoutChangingState() throws {
        let original = try chain()
        var state = try EditorState(document: original)
        try state.selectEdges(["ab", "cd"])
        let captured = state.snapshot
        for identities: [EdgeMidpointIdentity] in [
            [.init(originalEdgeID: "ab", nodeID: "midab", edgeID: "tailab")],
            [
                .init(originalEdgeID: "ab", nodeID: "midab", edgeID: "tailab"),
                .init(originalEdgeID: "bc", nodeID: "midbc", edgeID: "tailbc"),
            ],
        ] {
            XCTAssertThrowsError(try state.insertSelectedEdgeMidpoints(identities: identities)) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), captured.document.encoded())
            XCTAssertEqual(state.snapshot.selectedEdgeIDs, captured.selectedEdgeIDs)
            XCTAssertEqual(state.snapshot.selectionRevision, captured.selectionRevision)
            XCTAssertEqual(state.snapshot.previewIdentity, captured.previewIdentity)
            XCTAssertFalse(state.snapshot.canUndo)
        }
        var readonly = try EditorState(
            document: original.applying(.setPartState(id: "p", property: .locked, value: true)))
        try readonly.selectEdges(["ab", "cd"])
        let inspected = readonly.snapshot
        XCTAssertThrowsError(
            try readonly.insertSelectedEdgeMidpoints(identities: [
                .init(originalEdgeID: "ab", nodeID: "midab", edgeID: "tailab"),
                .init(originalEdgeID: "cd", nodeID: "midcd", edgeID: "tailcd"),
            ])
        ) { XCTAssertEqual($0 as? EditorError, .readOnlyNode) }
        XCTAssertEqual(readonly.snapshot.document.encoded(), inspected.document.encoded())
        XCTAssertEqual(readonly.snapshot.selectedEdgeIDs, inspected.selectedEdgeIDs)
        XCTAssertEqual(readonly.snapshot.selectionRevision, inspected.selectionRevision)
        XCTAssertEqual(readonly.snapshot.previewIdentity, inspected.previewIdentity)
        XCTAssertFalse(readonly.snapshot.canUndo)
    }

    func testMixedCutPayloadUsesExplicitNodesThenCombinedDeletionIsOneUndoStep() async throws {
        let original = try chain()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectGraph(nodes: ["a"], edges: ["cd"])
        XCTAssertTrue(selected.canCutNodes)
        let fragment = try await session.copySelection(onlyEditable: true)
        XCTAssertEqual(fragment.selectedNodeIDs, ["a"])
        XCTAssertEqual(try fragment.document.editorContents().nodes.map(\.id), ["a"])
        XCTAssertTrue(try fragment.document.editorContents().edges.isEmpty)
        let deleted = try await session.deleteSelection()
        XCTAssertEqual(Set(deleted.nodes.map(\.id)), ["b", "c", "d"])
        XCTAssertEqual(deleted.edges.map(\.id), ["bc"])
        XCTAssertTrue(deleted.selectedIDs.isEmpty)
        XCTAssertTrue(deleted.selectedEdgeIDs.isEmpty)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
    }

}
