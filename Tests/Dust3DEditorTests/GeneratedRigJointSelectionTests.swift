import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

final class GeneratedRigJointSelectionTests: XCTestCase {
    private func rig() -> GeneratedRig {
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let joints = ["Root zero", "é", "e\u{301}", "LeftUpperEyelid"].map { name in
            GeneratedRigJoint(
                name: name, parentIndex: nil, head: .zero, tail: .zero, capsuleRadius: 0, closingAngle: 0,
                restWorld: identity, inverseBind: identity)
        }
        return GeneratedRig(
            mesh: Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: ""), joints: joints,
            influences: [], eyelidsGenerated: true)
    }

    func testSameEpochKeepsSourceIndicesIncludingZeroAxisAndEyelidJoints() {
        let rig = rig()
        let revision = UUID()
        for index in rig.joints.indices {
            let selection = GeneratedRigJointSelection(revision: revision, index: index)
            XCTAssertEqual(selection.resolvedIndex(in: rig, revision: revision, incomingName: ""), index)
        }
        XCTAssertEqual(rig.joints[0].head, rig.joints[0].tail)
        XCTAssertEqual(rig.joints[3].name, "LeftUpperEyelid")
    }

    func testIncomingNamesUseExactUTF8InsteadOfCanonicalStringEquality() {
        let rig = rig()
        let revision = UUID()
        let stale = GeneratedRigJointSelection(revision: UUID(), index: 0)
        XCTAssertEqual("é", "e\u{301}")
        XCTAssertNotEqual(Data("é".utf8), Data("e\u{301}".utf8))
        XCTAssertEqual(stale.resolvedIndex(in: rig, revision: revision, incomingName: "é"), 1)
        XCTAssertEqual(stale.resolvedIndex(in: rig, revision: revision, incomingName: "e\u{301}"), 2)
        let current = GeneratedRigJointSelection(revision: revision, index: 2)
        XCTAssertEqual(current.resolvedIndex(in: rig, revision: revision, incomingName: "é"), 2)
    }

    func testNewEpochDiscardsIndexAndResolvesCurrentIncomingName() {
        let rig = rig()
        let selected = GeneratedRigJointSelection(revision: UUID(), index: 2)
        let replacement = UUID()
        XCTAssertEqual(selected.resolvedIndex(in: rig, revision: replacement, incomingName: "LeftUpperEyelid"), 3)
        XCTAssertNil(selected.resolvedIndex(in: rig, revision: replacement, incomingName: "Missing"))
        XCTAssertNil(selected.resolvedIndex(in: rig, revision: replacement, incomingName: ""))
    }

    func testExplicitNoneAppliesOnlyToItsOwnEpoch() {
        let rig = rig()
        let revision = UUID()
        let none = GeneratedRigJointSelection(revision: revision, index: nil)
        XCTAssertNil(none.resolvedIndex(in: rig, revision: revision, incomingName: "é"))
        XCTAssertEqual(none.resolvedIndex(in: rig, revision: UUID(), incomingName: "é"), 1)
    }

    func testInvalidSameEpochIndexFallsBackToIncomingWithoutIndexing() {
        let rig = rig()
        let revision = UUID()
        for index in [-1, rig.joints.count] {
            let invalid = GeneratedRigJointSelection(revision: revision, index: index)
            XCTAssertEqual(invalid.resolvedIndex(in: rig, revision: revision, incomingName: "e\u{301}"), 2)
            XCTAssertNil(invalid.resolvedIndex(in: rig, revision: revision, incomingName: "Missing"))
        }
    }
}
