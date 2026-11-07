import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class CanvasProfileMotionTests: XCTestCase {
    func testShiftedPositionsRequireCurrentSourceTokenAndLease() throws {
        var state = try makeState()
        let snapshot = state.snapshot
        let first = try XCTUnwrap(snapshot.nodes.first)
        let second = try XCTUnwrap(snapshot.nodes.last)
        let lease = UUID()
        let token = UUID()
        let shifted = NodePosition(x: 3, y: 4, z: 5)
        var motion = CanvasProfileMotion(snapshot: snapshot, lease: lease, token: token)
        XCTAssertEqual(motion.position(of: first, in: snapshot), first.value.position)
        XCTAssertTrue(motion.update(.shifted([first.id: shifted]), lease: lease, token: token, snapshot: snapshot))
        XCTAssertEqual(motion.position(of: first, in: snapshot), shifted)
        XCTAssertEqual(motion.position(of: second, in: snapshot), second.value.position)

        XCTAssertFalse(motion.update(.shifted([:]), lease: UUID(), token: token, snapshot: snapshot))
        XCTAssertFalse(motion.update(.shifted([:]), lease: lease, token: UUID(), snapshot: snapshot))
        XCTAssertEqual(motion.position(of: first, in: snapshot), shifted)
        try state.select(second.id)
        let changed = state.snapshot
        XCTAssertFalse(motion.update(.shifted([first.id: shifted]), lease: lease, token: token, snapshot: changed))
        XCTAssertEqual(motion.position(of: first, in: changed), first.value.position)
        XCTAssertEqual(changed.document.encoded(), snapshot.document.encoded())
    }

    func testOrdinaryDragSharesVerticalMotionAndPreservesCompanionHorizontalCoordinate() throws {
        let snapshot = try makeState().snapshot
        let anchor = try XCTUnwrap(snapshot.nodes.first)
        let other = try XCTUnwrap(snapshot.nodes.last)
        let bounds = CanvasBounds(nodes: snapshot.nodes)
        for (active, companion) in [(EditingPlane.front, EditingPlane.side), (.side, .front)] {
            let lease = UUID()
            let token = UUID()
            let projection = CanvasProjection(bounds: bounds, plane: active, width: 420, height: 240)
            let companionProjection = CanvasProjection(bounds: bounds, plane: companion, width: 300, height: 190)
            var lifecycle = NodeDragLifecycle()
            try lifecycle.begin(token: token, anchorID: anchor.id, snapshot: snapshot, projection: projection)
            lifecycle.update(token: token, snapshot: snapshot, translation: .init(x: 30, y: 20))
            let preview = try XCTUnwrap(lifecycle.preview)
            var motion = CanvasProfileMotion(snapshot: snapshot, lease: lease, token: token)
            XCTAssertTrue(motion.update(.ordinary(preview), lease: lease, token: token, snapshot: snapshot))
            let moved = motion.position(of: anchor, in: snapshot)
            let originalPoint = companionProjection.point(for: anchor.value.position)
            let movedPoint = companionProjection.point(for: moved)
            XCTAssertEqual(movedPoint.x, originalPoint.x, accuracy: 1e-12)
            XCTAssertEqual(
                movedPoint.y - originalPoint.y, 20 / projection.scale * companionProjection.scale, accuracy: 1e-12)
            XCTAssertEqual(motion.position(of: other, in: snapshot), other.value.position)
        }
    }

    private func makeState() throws -> EditorState {
        let xml = Data(
            "<canvas><nodes><node id='a' partId='p' x='0' y='1' z='2' radius='.1'/><node id='b' partId='p' x='1' y='2' z='3' radius='.2'/></nodes><parts><part id='p'/></parts></canvas>"
                .utf8)
        return try EditorState(document: Dust3DDocument(snapshotXML: xml))
    }
}
