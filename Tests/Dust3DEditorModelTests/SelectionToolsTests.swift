import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class SelectionToolsTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='keep'><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='0.1'/><node id='b' partId='p' x='2' y='4' z='6' radius='0.2'/><node id='c' partId='q' x='4' y='6' z='8' radius='0.3'/><node id='d' partId='r' x='1' y='2' z='3' radius='0.4'/></nodes><parts><part id='p'/><part id='q' locked='true'/><part id='r' visible='false'/></parts></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='2'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([255, 0]))
    }

    func testScalingUsesEditableCentroidAndOneUndoStep() throws {
        let original = try document()
        var state = try EditorState(document: original)
        state.selectAll()
        try state.scaleSelection(positionFactor: 2, radiusFactor: 3)
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: -1, y: -2, z: -3))
        XCTAssertEqual(try state.snapshot.document.node(id: "b").position, .init(x: 3, y: 6, z: 9))
        XCTAssertEqual(try state.snapshot.document.node(id: "a").radius, 0.3, accuracy: 0.000001)
        XCTAssertEqual(try state.snapshot.document.node(id: "b").radius, 0.6, accuracy: 0.000001)
        for id in ["c", "d"] { XCTAssertEqual(try state.snapshot.document.node(id: id), try original.node(id: id)) }
        XCTAssertEqual(state.snapshot.document.asset(named: "opaque"), Data([255, 0]))
        let edited = state.snapshot.document.encoded()
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        try state.redo()
        XCTAssertEqual(state.snapshot.document.encoded(), edited)
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c", "d"])
    }

    func testScalingHonorsEveryLockCombination() throws {
        let original = try document()
        for mask in 0..<16 {
            var state = try EditorState(document: original)
            try state.select(["a", "b"])
            for (index, lock) in EditingConstraint.allCases.enumerated() {
                state.setLock(lock, isLocked: mask & (1 << index) != 0)
            }
            try state.scaleSelection(positionFactor: 2, radiusFactor: 2)
            let a = try state.snapshot.document.node(id: "a")
            XCTAssertEqual(a.position.x, state.snapshot.locks.contains(.x) ? 0 : -1)
            XCTAssertEqual(a.position.y, state.snapshot.locks.contains(.y) ? 0 : -2)
            XCTAssertEqual(a.position.z, state.snapshot.locks.contains(.z) ? 0 : -3)
            XCTAssertEqual(a.radius, state.snapshot.locks.contains(.radius) ? 0.1 : 0.2)
            XCTAssertEqual(state.snapshot.canUndo, mask != 15)
        }
    }

    func testScaleValidationNoOpsAndSingleNode() throws {
        var state = try EditorState(document: document())
        try state.scaleSelection(positionFactor: 2, radiusFactor: 2)
        try state.select(["c", "d"])
        try state.scaleSelection(positionFactor: 2, radiusFactor: 2)
        XCTAssertFalse(state.snapshot.canUndo)
        try state.select("a")
        try state.scaleSelection(positionFactor: 5, radiusFactor: 2)
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: 0, y: 0, z: 0))
        try state.undo()
        try state.scaleSelection(positionFactor: 1, radiusFactor: 1)
        XCTAssertTrue(state.snapshot.canRedo)
        let before = state.snapshot.document.encoded()
        for invalid in [0.0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try state.scaleSelection(positionFactor: invalid, radiusFactor: 1)) {
                XCTAssertEqual($0 as? EditorError, .invalidScale)
            }
            XCTAssertThrowsError(try state.scaleSelection(positionFactor: 1, radiusFactor: invalid)) {
                XCTAssertEqual($0 as? EditorError, .invalidScale)
            }
        }
        try state.select(["a", "b"])
        XCTAssertThrowsError(try state.scaleSelection(positionFactor: 1_000_001, radiusFactor: 1))
        XCTAssertThrowsError(try state.scaleSelection(positionFactor: 1, radiusFactor: 100_000_000))
        XCTAssertEqual(state.snapshot.document.encoded(), before)
        XCTAssertTrue(state.snapshot.canRedo)
    }

    func testIdentityScalePreservesNonBinaryCoordinatesExactly() throws {
        var state = try EditorState(document: document())
        try state.edit(id: "a", position: .init(x: 0.1, y: 0.2, z: 0.3), radius: 0.1)
        try state.select(["a", "b"])
        let before = state.snapshot.document.encoded()
        let revision = state.snapshot.documentRevision
        try state.scaleSelection(positionFactor: 1, radiusFactor: 1)
        XCTAssertEqual(state.snapshot.document.encoded(), before)
        XCTAssertEqual(state.snapshot.documentRevision, revision)
    }

    func testLockedFieldsSkipProvisionalScaleOverflow() throws {
        let original = try document()
        var state = try EditorState(document: original)
        try state.select(["a", "b"])
        for lock in [EditingConstraint.x, .y, .z] { state.setLock(lock, isLocked: true) }
        try state.scaleSelection(positionFactor: 1e308, radiusFactor: 2)
        XCTAssertEqual(try state.snapshot.document.node(id: "b").position, try original.node(id: "b").position)
        XCTAssertEqual(try state.snapshot.document.node(id: "b").radius, 0.4)
        try state.undo()
        for lock in [EditingConstraint.x, .y, .z] { state.setLock(lock, isLocked: false) }
        state.setLock(.radius, isLocked: true)
        try state.scaleSelection(positionFactor: 2, radiusFactor: 1e308)
        XCTAssertEqual(try state.snapshot.document.node(id: "b").radius, 0.2)
        XCTAssertEqual(try state.snapshot.document.node(id: "b").position, .init(x: 3, y: 6, z: 9))
        try state.undo()
        try state.edit(id: "b", position: .init(x: 2, y: 0, z: 0), radius: 0.2)
        try state.select(["a", "b"])
        state.setLock(.x, isLocked: true)
        try state.scaleSelection(positionFactor: 1e308, radiusFactor: 1)
        XCTAssertEqual(try state.snapshot.document.node(id: "b").position, .init(x: 2, y: 0, z: 0))
    }

    func testMarqueeSelectsVisibleCentersInBothPlanesAndEitherDirection() throws {
        let nodes = try document().editorContents().nodes
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(bounds: CanvasBounds(nodes: nodes), plane: plane, width: 800, height: 600)
            let a = projection.point(for: nodes[0].value.position)
            let b = projection.point(for: nodes[1].value.position)
            let lower = CanvasPoint(x: min(a.x, b.x) - 1, y: min(a.y, b.y) - 1)
            let upper = CanvasPoint(x: max(a.x, b.x) + 1, y: max(a.y, b.y) + 1)
            for (start, end) in [
                (lower, upper), (upper, lower), (.init(x: lower.x, y: upper.y), .init(x: upper.x, y: lower.y)),
            ] {
                let rectangle = CanvasSelectionRectangle(from: start, to: end)
                XCTAssertEqual(projection.nodeIDs(in: rectangle, nodes: nodes), ["a", "b"])
            }
            let all = CanvasSelectionRectangle(from: .init(x: -1_000, y: -1_000), to: .init(x: 2_000, y: 2_000))
            XCTAssertEqual(projection.nodeIDs(in: all, nodes: nodes), ["a", "b", "c"])
            XCTAssertEqual(projection.nodeIDs(in: .init(from: a, to: a), nodes: nodes), ["a"])
            XCTAssertTrue(projection.nodeIDs(in: .init(from: .init(x: .nan, y: 0), to: b), nodes: nodes).isEmpty)
            XCTAssertTrue(
                projection.nodeIDs(in: .init(from: .init(x: 0, y: 0), to: .init(x: .infinity, y: 0)), nodes: nodes)
                    .isEmpty)
        }
    }

    @MainActor func testActorScaling() async throws {
        let session = EditorSession()
        _ = try await session.open(data: document().encoded())
        _ = try await session.select(Set(["a", "b"]))
        let scaled = try await session.scaleSelection(positionFactor: 2, radiusFactor: 1)
        XCTAssertEqual(try scaled.document.node(id: "a").position, .init(x: -1, y: -2, z: -3))
    }
}
