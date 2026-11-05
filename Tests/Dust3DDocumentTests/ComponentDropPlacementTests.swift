import Dust3DDocument
import Foundation
import XCTest

final class ComponentDropPlacementTests: XCTestCase {
    private func tree() throws -> [DocumentComponent] {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><components><component id='a'><component id='child'/></component><component id='b'/><component id='c'/><component id='d'/><component id='e'/><component id='café'/></components></canvas>"
                    .utf8
            )
        ).components()
    }

    func testNoncontiguousSelectionMovesAsOneBlockInSiblingOrder() throws {
        let components = try tree()
        XCTAssertEqual(
            try ComponentDropPlacementPlan(components: components, ids: ["d", "b", "b"], placement: .before("a"))
                .orderedSiblingIDs,
            ["b", "d", "a", "c", "e", "café"])
        XCTAssertEqual(
            try ComponentDropPlacementPlan(components: components, ids: ["d", "b"], placement: .after("e"))
                .orderedSiblingIDs,
            ["a", "c", "e", "b", "d", "café"])
    }

    func testSelectedAnchorResolvesAgainstOriginalBoundaryAndDetectsNoOp() throws {
        let components = try tree()
        let unchanged = try ComponentDropPlacementPlan(components: components, ids: ["b", "c"], placement: .after("c"))
        XCTAssertFalse(unchanged.changesOrder)
        let grouped = try ComponentDropPlacementPlan(components: components, ids: ["b", "d"], placement: .before("d"))
        XCTAssertEqual(grouped.orderedSiblingIDs, ["a", "c", "b", "d", "e", "café"])
    }

    func testEndUsesFullSiblingListAndRetainsSelectedDescendantWithAncestor() throws {
        let plan = try ComponentDropPlacementPlan(
            components: tree(), ids: ["child", "a"], placement: .end(parentID: nil))
        XCTAssertNil(plan.parentID)
        XCTAssertEqual(plan.orderedSiblingIDs, ["b", "c", "d", "e", "café", "a"])
    }

    func testMixedParentsAndRawAliasesReject() throws {
        let components = try tree()
        XCTAssertThrowsError(
            try ComponentDropPlacementPlan(components: components, ids: ["child", "b"], placement: .before("d"))
        ) { XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure) }
        XCTAssertThrowsError(
            try ComponentDropPlacementPlan(components: components, ids: ["a"], placement: .before("café"))
        ) { XCTAssertEqual($0 as? DocumentError, .missingComponent("café")) }
        XCTAssertThrowsError(
            try ComponentDropPlacementPlan(components: components, ids: ["café", "café"], placement: .before("a"))
        ) { XCTAssertEqual($0 as? DocumentError, .missingComponent("café")) }
    }
}

extension ComponentDropPlacementTests {
    func testPlacementPersistsSiblingOrderAndRetainsOpaqueSlots() throws {
        let xml =
            "<canvas><components><component id='a'><component id='child'/></component><!--slot--><opaque/><component id='b'/><component id='c'/></components></canvas>"
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let moved = try original.applying(.placeComponents(ids: ["c", "b"], placement: .before("a")))
        XCTAssertEqual(try moved.components().map(\.id), ["b", "c", "a", "child"])
        let text = String(decoding: moved.modelXML, as: UTF8.self)
        XCTAssertTrue(text.contains("<!--slot--><opaque"))
        XCTAssertTrue(
            try moved.applying(.placeComponents(ids: ["b", "c"], placement: .before("a"))).modelXML == moved.modelXML)
    }
}
