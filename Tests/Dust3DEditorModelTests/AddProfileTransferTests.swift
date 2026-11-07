import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class AddProfileTransferTests: XCTestCase {
    private func makeState() throws -> EditorState {
        let xml = """
            <canvas originX='2' originY='3' originZ='4'>
            <nodes><node id='a' partId='p' x='7' y='8' z='9' radius='0.1'/></nodes>
            <parts><part id='p'/></parts></canvas>
            """
        return try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
    }

    func testUnanchoredTransferKeepsRadiusAndUsesNewHiddenAxis() throws {
        let snapshot = try makeState().snapshot
        let bounds = CanvasBounds(nodes: snapshot.nodes, origin: snapshot.origin)
        let front = CanvasProjection(bounds: bounds, plane: .front, width: 500, height: 400)
        let side = CanvasProjection(bounds: bounds, plane: .side, width: 450, height: 200)
        let sample = NodePosition(x: 6, y: 5, z: 7)
        var placement = AddPlacementState()
        try placement.begin(snapshot: snapshot, projection: front, canvasHeight: 400)
        try placement.updatePointer(front.point(for: sample))
        try placement.adjustRadius(by: 8)
        let initial = try XCTUnwrap(placement.request())
        XCTAssertNil(initial.anchorID)
        XCTAssertEqual(initial.position.z, 4)
        XCTAssertEqual(initial.radius, 0.1, accuracy: 1e-12)

        placement.suspendProjectionForProfileChange()
        XCTAssertTrue(placement.isActive)
        XCTAssertNil(placement.projection)
        XCTAssertNil(placement.ghostPoint)
        XCTAssertNil(placement.ghostPosition)
        XCTAssertNil(placement.request())
        try placement.updatePointer(front.point(for: sample))
        XCTAssertNil(placement.request())

        try placement.reproject(snapshot: snapshot, projection: side, canvasHeight: 200)
        XCTAssertEqual(placement.projection?.plane, .side)
        XCTAssertEqual(placement.sceneRadius, 20, accuracy: 1e-12)
        XCTAssertNil(placement.request())
        try placement.updatePointer(side.point(for: sample))
        let transferred = try XCTUnwrap(placement.request())
        XCTAssertNotEqual(transferred.contextID, initial.contextID)
        XCTAssertTrue(placement.isCurrent(in: snapshot))
        XCTAssertEqual(transferred.position.x, 2)
        XCTAssertEqual(transferred.position.y, sample.y, accuracy: 1e-12)
        XCTAssertEqual(transferred.position.z, sample.z, accuracy: 1e-12)
        XCTAssertEqual(transferred.radius, initial.radius, accuracy: 1e-12)
    }

    func testAnchoredTransferKeepsAnchorAndAdjustedRadius() throws {
        var state = try makeState()
        try state.select("a")
        let snapshot = state.snapshot
        let bounds = CanvasBounds(nodes: snapshot.nodes, origin: snapshot.origin)
        let front = CanvasProjection(bounds: bounds, plane: .front, width: 500, height: 400)
        let side = CanvasProjection(bounds: bounds, plane: .side, width: 450, height: 200)
        let sample = NodePosition(x: 6, y: 5, z: 7)
        var placement = AddPlacementState()
        try placement.begin(snapshot: snapshot, projection: front, canvasHeight: 400)
        try placement.updatePointer(front.point(for: sample))
        try placement.adjustRadius(by: 12)
        let initial = try XCTUnwrap(placement.request())
        XCTAssertEqual(initial.anchorID, "a")
        XCTAssertEqual(initial.position.z, 9)

        placement.suspendProjectionForProfileChange()
        XCTAssertEqual(placement.anchorID, "a")
        try placement.reproject(snapshot: snapshot, projection: side, canvasHeight: 200)
        try placement.updatePointer(side.point(for: sample))
        let transferred = try XCTUnwrap(placement.request())
        XCTAssertEqual(transferred.anchorID, initial.anchorID)
        XCTAssertEqual(transferred.position.x, 7)
        XCTAssertEqual(transferred.radius, initial.radius, accuracy: 1e-12)
    }

    func testSmallerPreviewDoesNotEnlargeTransferredSubpointRadius() throws {
        let snapshot = try makeState().snapshot
        let bounds = CanvasBounds(nodes: snapshot.nodes, origin: snapshot.origin)
        let front = CanvasProjection(bounds: bounds, plane: .front, width: 500, height: 400)
        let side = CanvasProjection(bounds: bounds, plane: .side, width: 450, height: 200)
        let sample = NodePosition(x: 6, y: 5, z: 7)
        var placement = AddPlacementState()
        try placement.begin(snapshot: snapshot, projection: front, canvasHeight: 400)
        try placement.updatePointer(front.point(for: sample))
        try placement.adjustRadius(by: -100)
        XCTAssertEqual(placement.sceneRadius, 1)

        placement.suspendProjectionForProfileChange()
        try placement.reproject(snapshot: snapshot, projection: side, canvasHeight: 200)
        try placement.updatePointer(side.point(for: sample))
        XCTAssertEqual(placement.sceneRadius, 0.5)
        try placement.adjustRadius(by: -1)
        XCTAssertEqual(placement.sceneRadius, 0.5)
    }

    func testTransferRejectsAChangedSelectionWithoutInstallingProjection() throws {
        var state = try makeState()
        let bounds = CanvasBounds(nodes: state.snapshot.nodes, origin: state.snapshot.origin)
        let front = CanvasProjection(bounds: bounds, plane: .front, width: 500, height: 400)
        let side = CanvasProjection(bounds: bounds, plane: .side, width: 450, height: 200)
        var placement = AddPlacementState()
        try placement.begin(snapshot: state.snapshot, projection: front, canvasHeight: 400)
        placement.suspendProjectionForProfileChange()
        try state.select("a")

        XCTAssertThrowsError(try placement.reproject(snapshot: state.snapshot, projection: side, canvasHeight: 200)) {
            XCTAssertEqual($0 as? EditorError, .staleAddPlacement)
        }
        XCTAssertNil(placement.projection)
        XCTAssertNil(placement.request())
    }
}
