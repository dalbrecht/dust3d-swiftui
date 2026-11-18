import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class AdditiveRadiusTests: XCTestCase {
    private func document(radii: [Double] = [0.1, 0.4, 0.9, 0.2], partState: String = "") throws -> Dust3DDocument {
        let ids = ["a", "b", "c", "d"]
        let nodes = ids.enumerated().map {
            "<node id='\($0.element)' partId='p' x='\($0.offset)' y='\($0.offset+1)' z='\($0.offset+2)' radius='\(radii[$0.offset])' opaque='node'/>"
        }.joined()
        return try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes>\(nodes)</nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p' \(partState)/></parts><components><component id='component' linkData='p' linkDataType='partId'/></components></canvas>"
                    .utf8))
    }

    func testEqualAdditiveIncrementUsesMixedUnionOnceWithoutMovingOrChangingSelection() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.selectGraph(nodes: ["a", "b"], edges: ["ab", "bc"])
        let before = state.snapshot
        try state.adjustSelectionRadius(by: 0.05)
        for (node, expected) in zip(state.snapshot.nodes, [0.15, 0.45, 0.95, 0.2]) {
            XCTAssertEqual(node.value.radius, expected, accuracy: 1e-12)
        }
        XCTAssertEqual(state.snapshot.nodes.map(\.value.position), before.nodes.map(\.value.position))
        XCTAssertEqual(state.snapshot.selectedIDs, before.selectedIDs)
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision)
        let edited = state.snapshot.document.encoded()
        XCTAssertNotEqual(state.snapshot.previewIdentity, before.previewIdentity)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        try state.redo()
        XCTAssertEqual(state.snapshot.document.encoded(), edited)
    }

    func testClampsImportedValuesOnlyOnExplicitNonzeroEditAndNoopsPreserveRedoPreviewAndBytes() throws {
        let original = try document(radii: [0, 2, 0.001, 1])
        var state = try EditorState(document: original)
        state.selectAllNodes()
        let initial = state.snapshot
        try state.adjustSelectionRadius(by: 0)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertEqual(state.snapshot.previewIdentity, initial.previewIdentity)
        try state.adjustSelectionRadius(by: 0.1)
        XCTAssertEqual(state.snapshot.nodes.map(\.value.radius), [0.1, 1, 0.101, 1])
        try state.undo()
        let undone = state.snapshot
        try state.adjustSelectionRadius(by: 0)
        XCTAssertTrue(state.snapshot.canRedo)
        XCTAssertEqual(state.snapshot.previewIdentity, undone.previewIdentity)
        try state.redo()
        try state.select(Set(["a", "c"]))
        try state.adjustSelectionRadius(by: -1)
        XCTAssertEqual(state.snapshot.nodes.first { $0.id == "a" }?.value.radius, 0.001)
        try state.select(Set(["b", "d"]))
        let clamped = state.snapshot
        try state.adjustSelectionRadius(by: 100)
        XCTAssertEqual(state.snapshot.document.encoded(), clamped.document.encoded())
        XCTAssertEqual(state.snapshot.previewIdentity, clamped.previewIdentity)
    }

    func testPositionLocksDoNotBlockRadiusButRadiusLockAndReadonlyPartsSkipEdits() throws {
        var state = try EditorState(document: document())
        try state.selectEdges(["ab"])
        for lock in [EditingConstraint.x, .y, .z] { state.setLock(lock, isLocked: true) }
        XCTAssertTrue(state.snapshot.canAdjustSelectionRadius)
        try state.adjustSelectionRadius(by: 0.1)
        XCTAssertEqual(state.snapshot.nodes.first { $0.id == "a" }?.value.radius, 0.2)
        state.setLock(.radius, isLocked: true)
        XCTAssertFalse(state.snapshot.canAdjustSelectionRadius)
        let locked = state.snapshot
        try state.adjustSelectionRadius(by: 0.1)
        XCTAssertEqual(state.snapshot.document.encoded(), locked.document.encoded())
        for partState in ["locked='true'", "visible='false'", "disabled='true'"] {
            var readonly = try EditorState(document: document(partState: partState))
            readonly.selectAll()
            XCTAssertFalse(readonly.snapshot.canAdjustSelectionRadius)
            let before = readonly.snapshot
            try readonly.adjustSelectionRadius(by: 0.1)
            XCTAssertEqual(readonly.snapshot.document.encoded(), before.document.encoded())
            XCTAssertFalse(readonly.snapshot.canUndo)
        }
    }

    func testInvalidDeltaRejectsAtomicallyEvenWhenLockedOrNoSelection() throws {
        for selected in [false, true] {
            var state = try EditorState(document: document())
            if selected { state.selectAll() }
            state.setLock(.radius, isLocked: true)
            let before = state.snapshot
            for delta in [Double.nan, .infinity, -Double.infinity] {
                XCTAssertThrowsError(try state.adjustSelectionRadius(by: delta))
                XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
                XCTAssertEqual(state.snapshot.selectedEdgeIDs, before.selectedEdgeIDs)
                XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity)
                XCTAssertFalse(state.snapshot.canUndo)
            }
        }
    }

    func testHoveredNodeAdjustmentDoesNotSelectAndRejectsStaleSelectionAndOtherWindowTargets() throws {
        let original = try document()
        var state = try EditorState(document: original)
        XCTAssertTrue(state.snapshot.canAdjustNodeRadius(id: "b"))
        let target = CanvasAdjustmentTarget(snapshot: state.snapshot)
        try state.adjustNodeRadius(id: "b", by: 0.1, target: target)
        XCTAssertEqual(state.snapshot.nodes.first { $0.id == "b" }?.value.radius, 0.5)
        XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
        XCTAssertTrue(state.snapshot.selectedEdgeIDs.isEmpty)
        XCTAssertThrowsError(try state.adjustNodeRadius(id: "b", by: 0.1, target: target)) {
            XCTAssertEqual($0 as? EditorError, .staleCanvasAdjustment)
        }
        try state.undo()
        let selectedTarget = CanvasAdjustmentTarget(snapshot: state.snapshot)
        try state.select("a")
        XCTAssertFalse(state.snapshot.canAdjustNodeRadius(id: "b"))
        XCTAssertThrowsError(try state.adjustNodeRadius(id: "b", by: 0.1, target: selectedTarget))
        try state.select(nil)
        XCTAssertThrowsError(try state.adjustNodeRadius(id: "b", by: 0.1, target: selectedTarget))
        let other = try EditorState(document: original)
        XCTAssertThrowsError(
            try state.adjustNodeRadius(id: "b", by: 0.1, target: CanvasAdjustmentTarget(snapshot: other.snapshot)))
    }

    func testModifierWheelFactorScalesUnionPositionsOnlyAndIgnoresRadiusLock() async throws {
        let session = EditorSession()
        _ = try await session.open(data: document().encoded())
        let selected = try await session.selectEdges(["ab", "bc"])
        _ = try await session.setLock(.radius, isLocked: true)
        let current = try await session.moveSelection(by: .init(x: 0, y: 0, z: 0))
        let scaled = try await session.scaleSelection(
            positionFactor: 1 + 1 / 100.0, radiusFactor: 1, target: CanvasAdjustmentTarget(snapshot: current))
        XCTAssertEqual(scaled.nodes.map(\.value.radius), selected.nodes.map(\.value.radius))
        XCTAssertEqual(try XCTUnwrap(scaled.nodes.first { $0.id == "a" }).value.position.x, -0.01, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(scaled.nodes.first { $0.id == "c" }).value.position.x, 2.01, accuracy: 1e-12)
        XCTAssertEqual(
            scaled.nodes.first { $0.id == "d" }?.value.position, selected.nodes.first { $0.id == "d" }?.value.position)
    }
    func testSelectedAndHoverTargetsInvalidateOnRestoredSelectionConstraintsAndReplacedDocuments() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.selectEdges(["ab"])
        let selectedTarget = CanvasAdjustmentTarget(snapshot: state.snapshot)
        try state.toggleEdgeSelection("bc")
        try state.toggleEdgeSelection("bc")
        XCTAssertFalse(selectedTarget.isCurrent(in: state.snapshot))
        let before = state.snapshot
        XCTAssertThrowsError(try state.adjustSelectionRadius(by: 0.1, target: selectedTarget)) {
            XCTAssertEqual($0 as? EditorError, .staleCanvasAdjustment)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
        let scaleTarget = CanvasAdjustmentTarget(snapshot: state.snapshot)
        state.setLock(.x, isLocked: true)
        state.setLock(.x, isLocked: false)
        XCTAssertThrowsError(try state.scaleSelection(positionFactor: 1.01, radiusFactor: 1, target: scaleTarget))
        try state.select(nil)
        let hoverTarget = CanvasAdjustmentTarget(snapshot: state.snapshot)
        state.setLock(.radius, isLocked: true)
        state.setLock(.radius, isLocked: false)
        XCTAssertThrowsError(try state.adjustNodeRadius(id: "a", by: 0.1, target: hoverTarget))
        let other = try EditorState(document: original)
        XCTAssertFalse(hoverTarget.isCurrent(in: other.snapshot))
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testHoverRadiusIgnoresSidebarSelectionAndEditsOnlyTheHoveredNode() throws {
        let source = String(decoding: try document().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "id='d' partId='p'", with: "id='d' partId='q'")
            .replacingOccurrences(of: "</parts>", with: "<part id='q'/></parts>")
        let original = try Dust3DDocument(snapshotXML: Data(source.utf8))
        for selectsPart in [true, false] {
            var state = try EditorState(document: original)
            if selectsPart {
                try state.selectPart("p")
            } else {
                try state.selectComponent("component")
            }
            let before = state.snapshot
            XCTAssertTrue(before.canAdjustNodeRadius(id: "d"))
            try state.adjustNodeRadius(id: "d", by: 0.1, target: CanvasAdjustmentTarget(snapshot: before))
            let after = state.snapshot
            for (node, previous) in zip(after.nodes, before.nodes) {
                XCTAssertEqual(node.value.radius, previous.value.radius + (node.id == "d" ? 0.1 : 0), accuracy: 1e-12)
            }
            XCTAssertEqual(after.selectedPartID, before.selectedPartID)
            XCTAssertEqual(after.selectedComponentIDs, before.selectedComponentIDs)
            XCTAssertEqual(after.selectionRevision, before.selectionRevision)
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testHoverRejectsGraphSelectionAndInvalidIdentityButLockedReadonlyInputsAreNoops() throws {
        var state = try EditorState(document: document())
        for selectsNode in [true, false] {
            if selectsNode {
                try state.select("a")
            } else {
                try state.selectEdge("ab")
            }
            XCTAssertFalse(state.snapshot.canAdjustNodeRadius(id: "a"))
            let before = state.snapshot
            XCTAssertThrowsError(try state.adjustNodeRadius(id: "a", by: 0.1))
            XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
            XCTAssertEqual(state.snapshot.selectionRevision, before.selectionRevision)
        }
        try state.select(nil)
        XCTAssertFalse(state.snapshot.canAdjustNodeRadius(id: "missing"))
        XCTAssertThrowsError(try state.adjustNodeRadius(id: "missing", by: 0.1)) {
            XCTAssertEqual($0 as? DocumentError, .missingNode("missing"))
        }
        XCTAssertThrowsError(try state.adjustNodeRadius(id: "a", by: .nan))
        let before = state.snapshot
        state.setLock(.radius, isLocked: true)
        XCTAssertFalse(state.snapshot.canAdjustNodeRadius(id: "a"))
        try state.adjustNodeRadius(id: "a", by: 0.1)
        XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
        var readonly = try EditorState(document: document(partState: "locked='true'"))
        XCTAssertFalse(readonly.snapshot.canAdjustNodeRadius(id: "a"))
        try readonly.adjustNodeRadius(id: "a", by: 0.1)
        XCTAssertFalse(readonly.snapshot.canUndo)
    }

    func testMixedReadonlyParticipantsSkipOnlyTheirOwnRadiiAndExtremeFiniteDeltasSaturate() throws {
        let source = String(decoding: try document().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "id='c' partId='p'", with: "id='c' partId='q'")
            .replacingOccurrences(of: "id='d' partId='p'", with: "id='d' partId='q'")
            .replacingOccurrences(of: "id='bc' partId='p' from='b' to='c'", with: "id='cd' partId='q' from='c' to='d'")
            .replacingOccurrences(of: "</parts>", with: "<part id='q' locked='true'/></parts>")
        var state = try EditorState(document: Dust3DDocument(snapshotXML: Data(source.utf8)))
        try state.selectGraph(nodes: ["b", "c"], edges: ["ab", "cd"])
        let positions = state.snapshot.nodes.map(\.value.position)
        try state.adjustSelectionRadius(by: Double.greatestFiniteMagnitude)
        XCTAssertEqual(state.snapshot.nodes.map(\.value.radius), [1, 1, 0.9, 0.2])
        try state.adjustSelectionRadius(by: -Double.greatestFiniteMagnitude)
        XCTAssertEqual(state.snapshot.nodes.map(\.value.radius), [0.001, 0.001, 0.9, 0.2])
        XCTAssertEqual(state.snapshot.nodes.map(\.value.position), positions)
    }

    func testImportedRadiusClampDoesNotChangeIndependentMultiplicativeScaleSemantics() throws {
        var state = try EditorState(document: document())
        try state.selectEdges(["ab"])
        try state.scaleSelection(positionFactor: 1, radiusFactor: 2)
        XCTAssertEqual(Array(state.snapshot.nodes.prefix(2).map(\.value.radius)), [0.2, 0.8])
        try state.adjustSelectionRadius(by: 0.05)
        for (value, expected) in zip(state.snapshot.nodes.prefix(2).map(\.value.radius), [0.25, 0.85]) {
            XCTAssertEqual(value, expected, accuracy: 1e-12)
        }
    }

    func testSessionHoverAndSelectedRadiusTargetsStayInTheirOriginatingWindow() async throws {
        let first = EditorSession()
        let second = EditorSession()
        let original = try document()
        let firstSnapshot = try await first.open(data: original.encoded())
        let secondSnapshot = try await second.open(data: original.encoded())
        let firstTarget = CanvasAdjustmentTarget(snapshot: firstSnapshot)
        let adjusted = try await first.adjustNodeRadius(id: "a", by: 0.01, target: firstTarget)
        XCTAssertTrue(adjusted.selectedIDs.isEmpty)
        do {
            _ = try await second.adjustNodeRadius(id: "a", by: 0.01, target: firstTarget)
            XCTFail("A different window target must reject")
        } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }
        let secondSelected = try await second.selectEdges(["bc"])
        let selectedTarget = CanvasAdjustmentTarget(snapshot: secondSelected)
        let changed = try await second.adjustSelectionRadius(by: 0.01, target: selectedTarget)
        XCTAssertEqual(
            changed.nodes.first { $0.id == "a" }?.value.radius,
            secondSnapshot.nodes.first { $0.id == "a" }?.value.radius)
        XCTAssertNotEqual(
            changed.nodes.first { $0.id == "b" }?.value.radius,
            secondSnapshot.nodes.first { $0.id == "b" }?.value.radius)
        let firstUndone = try await first.undo()
        XCTAssertEqual(firstUndone.document.encoded(), original.encoded())
        XCTAssertFalse(firstUndone.canUndo)
    }

    func testBothClampedNoopsPreserveExistingRedoAndPreviewIdentity() throws {
        let original = try document(radii: [1, 0.001, 0.2, 0.3])
        var state = try EditorState(document: original)
        try state.select("c")
        try state.adjustSelectionRadius(by: 0.1)
        let edited = state.snapshot.document.encoded()
        try state.undo()
        for (id, delta) in [("a", 0.1), ("b", -0.1)] {
            try state.select(id)
            let before = state.snapshot
            try state.adjustSelectionRadius(by: delta)
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity)
            XCTAssertTrue(state.snapshot.canRedo)
            XCTAssertFalse(state.snapshot.canUndo)
        }
        try state.redo()
        XCTAssertEqual(state.snapshot.document.encoded(), edited)
    }

}
