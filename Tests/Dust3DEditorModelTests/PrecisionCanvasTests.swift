import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class PrecisionCanvasTests: XCTestCase {
    private func document(readonly: Bool = false, origin: Bool = true) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas \(origin ? "originX='2' originY='3' originZ='4'" : "")><nodes><node id='a' partId='p' x='0' y='1' z='2' radius='.1'/><node id='b' partId='q' x='2' y='3' z='4' radius='.2'/></nodes><edges><edge id='e' from='a' to='b' partId='p'/></edges><parts><part id='p'/><part id='q' \(readonly ? "locked='true'" : "")/></parts></canvas>
                """.utf8))
    }
    func testTargetedTranslationDeduplicatesMixedEndpointsRetainsRadiiSelectionAndExactUndo() throws {
        let source = try document()
        var state = try EditorState(document: source)
        try state.selectGraph(nodes: ["a"], edges: ["e"])
        try state.moveSelection(by: .init(x: 0.01, y: -0.02, z: 0), target: .init(snapshot: state.snapshot))
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: 0.01, y: 0.98, z: 2))
        XCTAssertEqual(try state.snapshot.document.node(id: "b").position, .init(x: 2.01, y: 2.98, z: 4))
        XCTAssertEqual(state.snapshot.selectedIDs, ["a"])
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["e"])
        XCTAssertEqual(try state.snapshot.document.node(id: "b").radius, 0.2)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }
    func testSignedPositionSpacingMatchesQtIncludingTinyHeightCollapseAndReflectionWithoutRadiusEdits() throws {
        for factor in [1.1, 0.9, 0, -1, -3] {
            var state = try EditorState(document: document())
            try state.selectEdges(["e"])
            try state.scaleSelectionPositions(factor: factor, target: .init(snapshot: state.snapshot))
            let a = try state.snapshot.document.node(id: "a")
            let b = try state.snapshot.document.node(id: "b")
            XCTAssertEqual(a.position.x, 1 - factor, accuracy: 1e-12)
            XCTAssertEqual(a.position.y, 2 - factor, accuracy: 1e-12)
            XCTAssertEqual(a.position.z, 3 - factor, accuracy: 1e-12)
            XCTAssertEqual(b.position.x, 1 + factor, accuracy: 1e-12)
            XCTAssertEqual(a.radius, 0.1)
            XCTAssertEqual(b.radius, 0.2)
        }
    }
    func testOriginNudgePreservesGraphAndSelectionUsesLocksAndOneUndo() throws {
        let source = try document(readonly: true)
        var state = try EditorState(document: source)
        try state.selectEdges(["e"])
        state.setLock(.x, isLocked: true)
        try state.nudgeOrigin(by: .init(x: 1, y: 0.01, z: -0.02), target: .init(snapshot: state.snapshot))
        XCTAssertEqual(state.snapshot.origin, .init(x: 2, y: 3.01, z: 3.98))
        for id in ["a", "b"] { XCTAssertEqual(try state.snapshot.document.node(id: id), try source.node(id: id)) }
        XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["e"])
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }
    func testStaleTargetsFiniteBoundsAndNoopsPreserveRedoWithoutPartialMutation() throws {
        var state = try EditorState(document: document())
        try state.selectEdges(["e"])
        let stale = CanvasAdjustmentTarget(snapshot: state.snapshot)
        state.setLock(.x, isLocked: true)
        state.setLock(.x, isLocked: false)
        XCTAssertThrowsError(try state.moveSelection(by: .init(x: 1, y: 0, z: 0), target: stale))
        XCTAssertThrowsError(try state.scaleSelectionPositions(factor: 2, target: stale))
        XCTAssertThrowsError(try state.nudgeOrigin(by: .init(x: 1, y: 0, z: 0), target: stale))
        let source = state.snapshot.document.encoded()
        for factor in [Double.nan, .infinity, 1_000_001] {
            XCTAssertThrowsError(try state.scaleSelectionPositions(factor: factor))
            XCTAssertEqual(state.snapshot.document.encoded(), source)
        }
        try state.scaleSelectionPositions(factor: 2)
        try state.undo()
        let preview = state.snapshot.previewIdentity
        try state.scaleSelectionPositions(factor: 1)
        try state.moveSelection(by: .init(x: 0, y: 0, z: 0))
        try state.nudgeOrigin(by: .init(x: 0, y: 0, z: 0))
        XCTAssertTrue(state.snapshot.canRedo)
        XCTAssertEqual(state.snapshot.previewIdentity, preview)
        var absent = try EditorState(document: document(origin: false))
        XCTAssertThrowsError(try absent.nudgeOrigin(by: .init(x: 1, y: 0, z: 0))) {
            XCTAssertEqual($0 as? EditorError, .unavailableOrigin)
        }
    }
    func testReadonlyParticipantsStayFixedAndAxisLocksConstrainMovementAndSpacing() throws {
        let source = try document(readonly: true)
        var state = try EditorState(document: source)
        try state.selectEdges(["e"])
        state.setLock(.y, isLocked: true)
        try state.moveSelection(by: .init(x: 0.1, y: 1, z: 0.2))
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: 0.1, y: 1, z: 2.2))
        XCTAssertEqual(try state.snapshot.document.node(id: "b"), try source.node(id: "b"))
        let unchanged = state.snapshot.document.encoded()
        try state.scaleSelectionPositions(factor: -2)
        XCTAssertEqual(
            state.snapshot.document.encoded(), unchanged, "Only one editable participant defines its own centroid")
    }
    func testSpacingKeepsEachLockedAxisFixedWhileOtherAxesScaleAndUndoRestoresBytes() throws {
        let cases: [(EditingConstraint, NodePosition, NodePosition)] = [
            (.x, .init(x: 0, y: 0, z: 1), .init(x: 2, y: 4, z: 5)),
            (.y, .init(x: -1, y: 1, z: 1), .init(x: 3, y: 3, z: 5)),
            (.z, .init(x: -1, y: 0, z: 2), .init(x: 3, y: 4, z: 4)),
        ]
        for (axis, expectedA, expectedB) in cases {
            let source = try document()
            var state = try EditorState(document: source)
            try state.selectEdges(["e"])
            state.setLock(axis, isLocked: true)
            try state.scaleSelectionPositions(factor: 2, target: .init(snapshot: state.snapshot))
            XCTAssertEqual(try state.snapshot.document.node(id: "a").position, expectedA)
            XCTAssertEqual(try state.snapshot.document.node(id: "b").position, expectedB)
            XCTAssertEqual(try state.snapshot.document.node(id: "a").radius, 0.1)
            XCTAssertEqual(try state.snapshot.document.node(id: "b").radius, 0.2)
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }
    func testEmptyReadonlyAndInvalidOriginOrTranslationRemainAtomic() throws {
        var empty = try EditorState(document: document())
        try empty.selectGraph(nodes: [], edges: [])
        try empty.scaleSelectionPositions(factor: 2)
        XCTAssertFalse(empty.snapshot.canUndo)
        try empty.select("a")
        let before = empty.snapshot.document.encoded()
        XCTAssertThrowsError(
            try empty.moveSelection(by: .init(x: .nan, y: 0, z: 0), target: .init(snapshot: empty.snapshot)))
        XCTAssertThrowsError(try empty.nudgeOrigin(by: .init(x: .infinity, y: 0, z: 0)))
        XCTAssertEqual(empty.snapshot.document.encoded(), before)
        XCTAssertFalse(empty.snapshot.canUndo)
    }

}
