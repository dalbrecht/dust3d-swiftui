import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class GeneratedRigHierarchyTests: XCTestCase {
    private func joint(_ name: String, parent: Int? = nil) -> GeneratedRigJoint {
        GeneratedRigJoint(
            name: name, parentIndex: parent, head: .zero, tail: .zero,
            capsuleRadius: 0, closingAngle: 0, restWorld: [], inverseBind: [])
    }

    func testEmptyHierarchyHasNoRootsAndIsEquatable() throws {
        let empty = try GeneratedRigHierarchy(joints: [])
        XCTAssertTrue(empty.roots.isEmpty)
        XCTAssertEqual(empty, try GeneratedRigHierarchy(joints: []))
    }

    func testForwardParentsPreserveRootAndSiblingSourceOrder() throws {
        let value = try GeneratedRigHierarchy(joints: [
            joint("First child", parent: 3), joint("Z root"),
            joint("Second child", parent: 3), joint("A root"),
        ])
        XCTAssertEqual(value.roots.map(\.index), [1, 3])
        XCTAssertEqual(value.roots.map(\.id), [1, 3])
        XCTAssertNil(value.roots[0].children)
        XCTAssertEqual(value.roots[1].children?.map(\.index), [0, 2])
    }

    func testNestedNodesKeepOriginalIndicesAndNilLeaves() throws {
        let joints = [joint("Grandchild", parent: 1), joint("Child", parent: 2), joint("Root")]
        let value = try GeneratedRigHierarchy(joints: joints)
        let root = try XCTUnwrap(value.roots.first)
        let child = try XCTUnwrap(root.children?.first)
        let leaf = try XCTUnwrap(child.children?.first)
        XCTAssertEqual([root.index, child.index, leaf.index], [2, 1, 0])
        XCTAssertNil(leaf.children)
        XCTAssertEqual(value, try GeneratedRigHierarchy(joints: joints))
    }

    func testZeroAxesCanonicalEquivalentNamesAndDerivedEyelidsStayPresent() throws {
        let joints = [
            joint("Head"), joint("é", parent: 0), joint("e\u{301}", parent: 0),
            joint("LeftUpperEyelid", parent: 0), joint("LeftLowerEyelid", parent: 0),
            joint("RightUpperEyelid", parent: 0), joint("RightLowerEyelid", parent: 0),
        ]
        let value = try GeneratedRigHierarchy(joints: joints)
        let children = try XCTUnwrap(value.roots.first?.children)
        XCTAssertEqual(children.map(\.index), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(children.map { Data(joints[$0.index].name.utf8) }, joints.dropFirst().map { Data($0.name.utf8) })
        XCTAssertTrue(joints.allSatisfy { $0.head == $0.tail })
    }

    func testNegativeMissingAndSelfParentsRejectWithTypedCause() {
        for parent in [-1, 1, 0] {
            XCTAssertThrowsError(try GeneratedRigHierarchy(joints: [joint("Only", parent: parent)])) {
                XCTAssertEqual($0 as? GeneratedRigHierarchyError, .invalidParent)
                XCTAssertFalse($0.localizedDescription.isEmpty)
            }
        }
    }

    func testCyclesDisconnectedFromValidRootsReject() {
        for parents in [[2, 1], [2, 3, 1]] {
            var joints = [joint("Root")]
            joints.append(contentsOf: parents.enumerated().map { joint("Cycle \($0.offset)", parent: $0.element) })
            XCTAssertThrowsError(try GeneratedRigHierarchy(joints: joints)) {
                XCTAssertEqual($0 as? GeneratedRigHierarchyError, .cyclicParents)
                XCTAssertFalse($0.localizedDescription.isEmpty)
            }
        }
    }

    func testSmallFlatCountBoundaryMatchesCopiedNativeJointLimit() throws {
        let maximum = (0..<256).map { joint("Root \($0)") }
        XCTAssertEqual(try GeneratedRigHierarchy(joints: maximum).roots.count, 256)
        XCTAssertThrowsError(try GeneratedRigHierarchy(joints: maximum + [joint("Extra")])) {
            XCTAssertEqual($0 as? GeneratedRigHierarchyError, .invalidJointCount)
            XCTAssertFalse($0.localizedDescription.isEmpty)
        }
    }

    func testPrecancelledEmptyInputThrowsInsteadOfPublishingEmptyHierarchy() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try GeneratedRigHierarchy(joints: [])
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
