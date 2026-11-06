import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

@MainActor
final class GeneratedRigHierarchyDisclosureTests: XCTestCase {
    private func hierarchy() throws -> GeneratedRigHierarchy {
        let values: [(String, Int?)] = [("é", 2), ("Same", nil), ("e\u{301}", 3), ("Same", nil), ("Same", 1)]
        return try GeneratedRigHierarchy(
            joints: values.map { name, parent in
                GeneratedRigJoint(
                    name: name, parentIndex: parent, head: .zero, tail: .zero,
                    capsuleRadius: 0, closingAngle: 0, restWorld: [], inverseBind: [])
            })
    }

    func testForwardParentPathsUseSourceIndicesDespiteDuplicateNamesAndZeroAxes() throws {
        let revision = UUID()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: try hierarchy(), revision: revision, selected: 0)
        XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.expanded, [2, 3])
        XCTAssertTrue(state.isExpanded)
        let reveal = try XCTUnwrap(state.reveal)
        XCTAssertEqual(reveal.revision, revision)
        XCTAssertEqual(reveal.index, 0)
        XCTAssertTrue(state.accepts(reveal))
    }

    func testSelectionChangeExpandsOnlyItsAncestorsAndPreservesUnrelatedExpansion() throws {
        let revision = UUID()
        let tree = try hierarchy()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: tree, revision: revision, selected: 0)
        state.sync(hierarchy: tree, revision: revision, selected: 4)
        XCTAssertEqual(state.expanded, [1, 2, 3])
        XCTAssertEqual(state.selectedIndex, 4)
        XCTAssertTrue(state.accepts(try XCTUnwrap(state.reveal)))
        state.sync(hierarchy: tree, revision: revision, selected: 1)
        XCTAssertEqual(state.expanded, [1, 2, 3])
        XCTAssertTrue(state.accepts(try XCTUnwrap(state.reveal)))
    }

    func testUnchangedSelectionPreservesManualCollapseUntilExplicitReveal() throws {
        let revision = UUID()
        let tree = try hierarchy()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: tree, revision: revision, selected: 0)
        let original = try XCTUnwrap(state.reveal)
        state.setExpanded(false, index: 2, revision: revision)
        XCTAssertNil(state.reveal)
        state.sync(hierarchy: tree, revision: revision, selected: 0)
        XCTAssertEqual(state.expanded, [3])
        XCTAssertFalse(state.accepts(original))
        state.setExpanded(false, index: nil, revision: revision)
        state.sync(hierarchy: tree, revision: revision, selected: 0)
        XCTAssertFalse(state.isExpanded)
        XCTAssertNil(state.reveal)
        state.revealSelected(revision: revision)
        let current = try XCTUnwrap(state.reveal)
        XCTAssertNotEqual(current.id, original.id)
        XCTAssertEqual(state.expanded, [2, 3])
        XCTAssertTrue(state.isExpanded)
        XCTAssertTrue(state.accepts(current))
    }

    func testRepeatedRevealAndSelectionABARejectObsoleteScrollTokens() throws {
        let revision = UUID()
        let tree = try hierarchy()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: tree, revision: revision, selected: 0)
        let first = try XCTUnwrap(state.reveal)
        state.revealSelected(revision: revision)
        let repeated = try XCTUnwrap(state.reveal)
        XCTAssertNotEqual(first.id, repeated.id)
        XCTAssertFalse(state.accepts(first))
        state.sync(hierarchy: tree, revision: revision, selected: 4)
        state.sync(hierarchy: tree, revision: revision, selected: 0)
        let returned = try XCTUnwrap(state.reveal)
        XCTAssertNotEqual(returned.id, repeated.id)
        XCTAssertFalse(state.accepts(repeated))
        XCTAssertTrue(state.accepts(returned))
    }

    func testRevisionChangeResetsExpansionAndRejectsStaleActions() throws {
        let tree = try hierarchy()
        let oldRevision = UUID()
        let nextRevision = UUID()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: tree, revision: oldRevision, selected: 0)
        let old = try XCTUnwrap(state.reveal)
        state.sync(hierarchy: tree, revision: nextRevision, selected: 4)
        let current = try XCTUnwrap(state.reveal)
        XCTAssertEqual(state.expanded, [1])
        XCTAssertFalse(state.accepts(old))
        state.setExpanded(false, index: 1, revision: oldRevision)
        state.setExpanded(false, index: nil, revision: oldRevision)
        state.revealSelected(revision: oldRevision)
        XCTAssertEqual(state.reveal, current)
        XCTAssertTrue(state.accepts(current))
    }

    func testNilOrInvalidSelectionPreservesDisclosureButDoesNotReveal() throws {
        let revision = UUID()
        let tree = try hierarchy()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: tree, revision: revision, selected: 0)
        let old = try XCTUnwrap(state.reveal)
        for selection: Int? in [nil, -1, 99] {
            state.sync(hierarchy: tree, revision: revision, selected: selection)
            XCTAssertNil(state.selectedIndex)
            XCTAssertNil(state.reveal)
            XCTAssertEqual(state.expanded, [2, 3])
            XCTAssertTrue(state.isExpanded)
            state.revealSelected(revision: revision)
            XCTAssertNil(state.reveal)
            XCTAssertFalse(state.accepts(old))
        }
    }

    func testManualChangesInvalidateRevealWhileNoOpsAndInvalidRowsDoNot() throws {
        let revision = UUID()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: try hierarchy(), revision: revision, selected: 0)
        let reveal = try XCTUnwrap(state.reveal)
        state.setExpanded(true, index: 3, revision: revision)
        state.setExpanded(true, index: 0, revision: revision)
        state.setExpanded(false, index: 99, revision: revision)
        state.setExpanded(true, index: nil, revision: revision)
        XCTAssertTrue(state.accepts(reveal))
        state.setExpanded(true, index: 1, revision: revision)
        XCTAssertNil(state.reveal)
        XCTAssertFalse(state.accepts(reveal))
        XCTAssertEqual(state.expanded, [1, 2, 3])
    }

    func testMissingHierarchyOrRevisionClearsAllAndExplicitInvalidationOnlyClearsToken() throws {
        let tree = try hierarchy()
        let state = GeneratedRigHierarchyDisclosure()
        for missingHierarchy in [true, false] {
            let revision = UUID()
            state.sync(hierarchy: tree, revision: revision, selected: 0)
            state.invalidateReveal()
            XCTAssertNil(state.reveal)
            XCTAssertEqual(state.selectedIndex, 0)
            XCTAssertEqual(state.expanded, [2, 3])
            XCTAssertTrue(state.isExpanded)
            state.sync(
                hierarchy: missingHierarchy ? nil : tree, revision: missingHierarchy ? revision : nil, selected: 0)
            XCTAssertNil(state.revision)
            XCTAssertNil(state.selectedIndex)
            XCTAssertNil(state.reveal)
            XCTAssertTrue(state.expanded.isEmpty)
            XCTAssertFalse(state.isExpanded)
        }
    }

    func testEmptyHierarchyAndForgedTokensCannotRevealRows() throws {
        let revision = UUID()
        let state = GeneratedRigHierarchyDisclosure()
        state.sync(hierarchy: try GeneratedRigHierarchy(joints: []), revision: revision, selected: 0)
        XCTAssertNil(state.selectedIndex)
        XCTAssertNil(state.reveal)
        XCTAssertFalse(state.accepts(.init(id: UUID(), revision: revision, index: 0)))
        state.sync(hierarchy: try hierarchy(), revision: revision, selected: 1)
        // A generation's hierarchy is immutable; a new tree needs a new epoch.
        state.sync(hierarchy: try hierarchy(), revision: UUID(), selected: 1)
        let current = try XCTUnwrap(state.reveal)
        XCTAssertFalse(state.accepts(.init(id: current.id, revision: current.revision, index: 3)))
    }
}
