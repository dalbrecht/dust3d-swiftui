import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class SelectionTransformInputTests: XCTestCase {
    func testMoveZerosLockedAxesBeforeValidatingActiveAxes() {
        XCTAssertEqual(
            SelectionTransformInput.move(delta: .init(x: .nan, y: -2, z: .infinity), locks: [.x, .z, .radius]),
            NodePosition(x: 0, y: -2, z: 0))
        XCTAssertNil(SelectionTransformInput.move(delta: .init(x: .nan, y: 2, z: 3), locks: [.z]))
        XCTAssertNil(SelectionTransformInput.move(delta: .init(x: 1, y: .infinity, z: 3), locks: [.x]))
        XCTAssertNil(SelectionTransformInput.move(delta: .init(x: 1, y: 2, z: -.infinity), locks: [.y]))
        XCTAssertNil(SelectionTransformInput.move(delta: .init(x: 1, y: 2, z: 3), locks: [.x, .y, .z]))
    }

    func testScaleUsesNeutralFactorsForFullyLockedChannels() throws {
        let positionOnly = try XCTUnwrap(
            SelectionTransformInput.scale(positionFactor: 2, radiusFactor: 0, locks: [.radius]))
        XCTAssertEqual(positionOnly.positionFactor, 2)
        XCTAssertEqual(positionOnly.radiusFactor, 1)

        let radiusOnly = try XCTUnwrap(
            SelectionTransformInput.scale(positionFactor: .nan, radiusFactor: 3, locks: [.x, .y, .z]))
        XCTAssertEqual(radiusOnly.positionFactor, 1)
        XCTAssertEqual(radiusOnly.radiusFactor, 3)

        XCTAssertNil(
            SelectionTransformInput.scale(positionFactor: 2, radiusFactor: 3, locks: [.x, .y, .z, .radius]))
    }

    func testScaleRejectsInvalidFactorsInActiveChannels() {
        for invalid in [0.0, -1, Double.nan, .infinity] {
            XCTAssertNil(SelectionTransformInput.scale(positionFactor: invalid, radiusFactor: 2, locks: [.x, .z]))
            XCTAssertNil(
                SelectionTransformInput.scale(positionFactor: 2, radiusFactor: invalid, locks: [.x, .y, .z]))
        }
    }

    func testPreparedScaleAppliesWithLockedInvalidDraftAndDirectAPIStillRejectsIt() throws {
        let model = """
            <canvas><nodes>
            <node id='a' partId='p' x='0' y='0' z='0' radius='0.1'/>
            <node id='b' partId='p' x='2' y='4' z='6' radius='0.2'/>
            </nodes><parts><part id='p'/></parts></canvas>
            """
        let document = try Dust3DDocument(snapshotXML: Data(model.utf8))
        var state = try EditorState(document: document)
        try state.select(["a", "b"])
        state.setLock(.radius, isLocked: true)

        XCTAssertThrowsError(try state.scaleSelection(positionFactor: 2, radiusFactor: 0)) {
            XCTAssertEqual($0 as? EditorError, .invalidScale)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), document.encoded())
        XCTAssertFalse(state.snapshot.canUndo)

        let factors = try XCTUnwrap(
            SelectionTransformInput.scale(positionFactor: 2, radiusFactor: 0, locks: state.snapshot.locks))
        try state.scaleSelection(positionFactor: factors.positionFactor, radiusFactor: factors.radiusFactor)
        let edited = try state.snapshot.document.node(id: "b")
        XCTAssertEqual(edited.position, .init(x: 3, y: 6, z: 9))
        XCTAssertEqual(edited.radius, 0.2)
        XCTAssertTrue(state.snapshot.canUndo)
    }
}
