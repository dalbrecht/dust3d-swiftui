import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class CombinedAnimationExportPlanTests: XCTestCase {
    func testPreservesClipAndSurfaceOrderWithCaseInsensitiveCollisions() throws {
        let clips = try animations(
            "<animation id='a' name='Swim' type='FishSwim'/><animation id='b' name='swim' type='FishSwim'/>")
        let plan = try CombinedAnimationExportPlan(modelName: "Fish", animations: clips, surfaces: ["Stone", "Water"])
        XCTAssertEqual(plan.outputs.map(\.animation.id), ["a", "a", "b", "b"])
        XCTAssertEqual(plan.outputs.map(\.surface), ["Stone", "Water", "Stone", "Water"])
        XCTAssertEqual(
            plan.outputs.map(\.filename),
            ["Fish_Swim_Stone.wav", "Fish_Swim_Water.wav", "Fish_swim_Stone_2.wav", "Fish_swim_Water_2.wav"])
    }

    func testKeepsNamesSingleComponentAndBoundsEncodedLength() throws {
        let clips = try animations("<animation id='a' name='../pond:水' type='FishSwim'/>")
        let plan = try CombinedAnimationExportPlan(
            modelName: String(repeating: "魚", count: 100) + "/escape", animations: clips, surfaces: ["Water"])
        let filename = try XCTUnwrap(plan.outputs.first?.filename)
        XCTAssertTrue(filename.hasSuffix("_Water.wav"))
        XCTAssertLessThanOrEqual(filename.utf8.count, 255)
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.hasPrefix("."))
    }

    func testRejectsOversizedPlanBeforePreparingOutputs() throws {
        let clips = try animations(
            "<animation id='a' name='A' type='FishIdle'/><animation id='b' name='B' type='FishIdle'/>")
        XCTAssertThrowsError(
            try CombinedAnimationExportPlan(
                modelName: "Fish", animations: clips, surfaces: ["Stone", "Water"], maximumOutputs: 3)
        ) { XCTAssertEqual($0 as? CombinedAnimationExportPlan.Failure, .outputLimit) }
    }

    func testPreservesByteDistinctClipIdentitiesAndRejectsDuplicateRequests() throws {
        let clips = try animations(
            "<animation id='é' name='é'/><animation id='e&#x301;' name='e&#x301;'/>")
        let plan = try CombinedAnimationExportPlan(modelName: "Fish", animations: clips, surfaces: ["Water"])
        XCTAssertEqual(plan.outputs.map { Array($0.animation.id.utf8) }, [[195, 169], [101, 204, 129]])
        XCTAssertEqual(plan.outputs.map(\.filename), ["Fish_é_Water.wav", "Fish_é_Water_2.wav"])
        XCTAssertThrowsError(
            try CombinedAnimationExportPlan(modelName: "Fish", animations: [clips[0], clips[0]], surfaces: ["Water"])
        ) { XCTAssertEqual($0 as? CombinedAnimationExportPlan.Failure, .duplicateAnimation) }
        XCTAssertThrowsError(
            try CombinedAnimationExportPlan(modelName: "Fish", animations: clips, surfaces: ["Water", "Water"])
        ) { XCTAssertEqual($0 as? CombinedAnimationExportPlan.Failure, .duplicateSurface) }
    }

    func testEmptyPlanAndBlankNameFallbacks() throws {
        let clips = try animations("<animation id='unnamed'/>")
        let empty = try CombinedAnimationExportPlan(modelName: ".", animations: clips, surfaces: [], maximumOutputs: 0)
        XCTAssertTrue(empty.outputs.isEmpty)
        let unnamed = try CombinedAnimationExportPlan(modelName: ".", animations: clips, surfaces: ["Water"])
        XCTAssertEqual(unnamed.outputs.map(\.filename), ["Model_Animation_Water.wav"])
    }

    private func animations(_ rows: String) throws -> [DocumentAnimation] {
        try Dust3DDocument(snapshotXML: Data("<canvas><animations>\(rows)</animations></canvas>".utf8)).animations()
    }
}
