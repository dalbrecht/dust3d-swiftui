import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class DescendantRotationTests: XCTestCase {
    private func document(
        origin: String = "originX='0' originY='0' originZ='0'", childFlags: String = "", pivotFlags: String = "",
        cycle: Bool = false, isolated: Bool = false
    ) throws -> Dust3DDocument {
        let childPart = childFlags.isEmpty ? "p" : "locked"
        let edges =
            isolated
            ? ""
            : "<edge id='ap' from='parent' to='pivot'/><edge id='pc' from='pivot' to='child'/><edge id='cl' from='child' to='leaf'/>"
                + (cycle ? "<edge id='la' from='leaf' to='parent'/>" : "")
        let model = Data(
            "<canvas \(origin) future='keep'><nodes><node id='parent' partId='p' x='0' y='0' z='0' radius='.1'/><node id='pivot' partId='p' x='1' y='1' z='1' radius='.2'/><node id='child' partId='\(childPart)' x='2' y='2' z='2' radius='.3'/><node id='leaf' partId='p' x='3' y='2' z='4' radius='.4'/><node id='other' partId='q' x='5' y='-2' z='7' radius='.5'/></nodes><edges>\(edges)</edges><parts><part id='p' \(pivotFlags)/><part id='locked' \(childFlags)/><part id='q'/></parts><future value='preserve'/></canvas>"
                .utf8)
        let asset = Data([0, 255, 17, 42])
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='future.bin' offset='\(model.count)' size='\(asset.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + asset)
    }

    func testEachQuarterTurnKeepsPivotParentSelectionRadiiAndAssetsWithExactHistory() throws {
        let original = try document()
        let cases: [(DescendantRotation, NodePosition, NodePosition)] = [
            (.frontClockwise, .init(x: 0, y: 2, z: 2), .init(x: 0, y: 3, z: 4)),
            (.frontCounterclockwise, .init(x: 2, y: 0, z: 2), .init(x: 2, y: -1, z: 4)),
            (.sideClockwise, .init(x: 2, y: 2, z: 0), .init(x: 3, y: 4, z: 0)),
            (.sideCounterclockwise, .init(x: 2, y: 0, z: 2), .init(x: 3, y: -2, z: 2)),
        ]
        XCTAssertEqual(cases.count, DescendantRotation.allCases.count)
        for (rotation, child, leaf) in cases {
            var state = try EditorState(document: original)
            try state.select("pivot")
            XCTAssertTrue(state.snapshot.canRotateDescendants)
            try state.rotateDescendants(rotation)
            XCTAssertEqual(try state.snapshot.document.node(id: "child").position, child)
            XCTAssertEqual(try state.snapshot.document.node(id: "leaf").position, leaf)
            for id in ["parent", "pivot", "other"] {
                XCTAssertEqual(try state.snapshot.document.node(id: id), try original.node(id: id))
            }
            for node in try original.editorContents().nodes {
                XCTAssertEqual(try state.snapshot.document.node(id: node.id).radius, node.value.radius)
            }
            XCTAssertEqual(state.snapshot.selectedIDs, ["pivot"])
            XCTAssertEqual(state.snapshot.origin, try original.origin())
            XCTAssertEqual(state.snapshot.document.encoded().suffix(4), Data([0, 255, 17, 42]))
            XCTAssertTrue(String(decoding: state.snapshot.document.modelXML, as: UTF8.self).contains("future='keep'"))
            let saved = state.snapshot.document.encoded()
            XCTAssertEqual(try Dust3DDocument(data: saved).node(id: "leaf").position, leaf)
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
            try state.redo()
            XCTAssertEqual(state.snapshot.document.encoded(), saved)
        }
    }

    func testOriginChoosesParentInThreeDimensionsWithStableNodeOrderTiesAndCycles() throws {
        // Front-projected distances favor parent; full 3D distance favors child.
        let original = try document(origin: "originX='0' originY='0' originZ='4'")
        var reversedParent = try EditorState(document: original)
        try reversedParent.select("pivot")
        try reversedParent.rotateDescendants(.frontClockwise)
        XCTAssertEqual(try reversedParent.snapshot.document.node(id: "child"), try original.node(id: "child"))
        XCTAssertEqual(try reversedParent.snapshot.document.node(id: "leaf"), try original.node(id: "leaf"))
        XCTAssertEqual(try reversedParent.snapshot.document.node(id: "parent").position, .init(x: 2, y: 0, z: 0))
        // Both direct neighbors are equally distant from the pivot's origin; source node order picks parent first.
        var tied = try EditorState(document: document(origin: "originX='1' originY='1' originZ='1'"))
        try tied.select("pivot")
        try tied.rotateDescendants(.frontClockwise)
        XCTAssertEqual(try tied.snapshot.document.node(id: "parent").position, .init(x: 0, y: 0, z: 0))
        XCTAssertEqual(try tied.snapshot.document.node(id: "child").position, .init(x: 0, y: 2, z: 2))
        var cycle = try EditorState(document: document(cycle: true))
        try cycle.select("pivot")
        try cycle.rotateDescendants(.frontClockwise)
        XCTAssertEqual(try cycle.snapshot.document.node(id: "parent").position, .init(x: 2, y: 0, z: 0))
        XCTAssertEqual(try cycle.snapshot.document.node(id: "pivot").position, .init(x: 1, y: 1, z: 1))
        XCTAssertEqual(cycle.snapshot.edges.count, 4)
    }

    func testEndpointRotatesWholeConnectedChainAndIsolatedPivotPreservesRedo() throws {
        let original = try document()
        var endpoint = try EditorState(document: original)
        try endpoint.select("parent")
        try endpoint.rotateDescendants(.frontClockwise)
        XCTAssertEqual(try endpoint.snapshot.document.node(id: "pivot").position, .init(x: -1, y: 1, z: 1))
        XCTAssertEqual(try endpoint.snapshot.document.node(id: "leaf").position, .init(x: -2, y: 3, z: 4))
        XCTAssertEqual(try endpoint.snapshot.document.node(id: "other"), try original.node(id: "other"))
        var isolated = try EditorState(document: document(isolated: true))
        try isolated.select("pivot")
        try isolated.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
        try isolated.undo()
        let before = isolated.snapshot.document.encoded()
        try isolated.rotateDescendants(.sideCounterclockwise)
        XCTAssertEqual(isolated.snapshot.document.encoded(), before)
        XCTAssertTrue(isolated.snapshot.canRedo)
    }

    func testLocksAndReadonlyTraversalKeepRestrictedGeometryFixed() throws {
        let original = try document()
        for locks: Set<EditingConstraint> in [[], [.x], [.y], [.z], [.radius], [.x, .y, .z]] {
            var state = try EditorState(document: original)
            try state.select("pivot")
            try state.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
            try state.undo()
            for lock in locks { state.setLock(lock, isLocked: true) }
            try state.rotateDescendants(.frontClockwise)
            XCTAssertEqual(
                try state.snapshot.document.node(id: "child").position, .init(x: locks.contains(.x) ? 2 : 0, y: 2, z: 2)
            )
            XCTAssertEqual(
                try state.snapshot.document.node(id: "leaf").position,
                .init(x: locks.contains(.x) ? 3 : 0, y: locks.contains(.y) ? 2 : 3, z: 4))
            var side = try EditorState(document: original)
            try side.select("pivot")
            try side.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
            try side.undo()
            for lock in locks { side.setLock(lock, isLocked: true) }
            try side.rotateDescendants(.sideClockwise)
            XCTAssertEqual(
                try side.snapshot.document.node(id: "child").position, .init(x: 2, y: 2, z: locks.contains(.z) ? 2 : 0))
            XCTAssertEqual(
                try side.snapshot.document.node(id: "leaf").position,
                .init(x: 3, y: locks.contains(.y) ? 2 : 4, z: locks.contains(.z) ? 4 : 0))
            if locks.isSuperset(of: [.x, .y, .z]) {
                XCTAssertFalse(state.snapshot.canUndo)
                XCTAssertFalse(side.snapshot.canUndo)
                XCTAssertTrue(state.snapshot.canRedo)
                XCTAssertTrue(side.snapshot.canRedo)
            }
            XCTAssertEqual(state.snapshot.locks, locks)
            XCTAssertEqual(try state.snapshot.document.node(id: "child").radius, 0.3)
        }
        // Pure metadata traversal can cross a readonly node; this synthetic cross-part graph is not an engine-support claim.
        for flags in ["locked='true'", "visible='false'", "disabled='true'"] {
            let original = try document(childFlags: flags)
            var state = try EditorState(document: original)
            try state.select("pivot")
            try state.rotateDescendants(.frontClockwise)
            XCTAssertEqual(try state.snapshot.document.node(id: "child"), try original.node(id: "child"))
            XCTAssertEqual(try state.snapshot.document.node(id: "leaf").position, .init(x: 0, y: 3, z: 4))
        }
    }

    func testInvalidSelectionOriginReadonlyPivotAndOverflowRejectAtomically() throws {
        let original = try document()
        for selection: Set<String> in [[], ["parent", "pivot"]] {
            var state = try EditorState(document: original)
            try state.select(selection)
            XCTAssertFalse(state.snapshot.canRotateDescendants)
            XCTAssertThrowsError(try state.rotateDescendants(.frontClockwise)) {
                XCTAssertEqual($0 as? EditorError, .invalidPivotSelection)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
        var missing = try EditorState(document: document(origin: "originX='unsupported'"))
        try missing.select("pivot")
        XCTAssertFalse(missing.snapshot.canRotateDescendants)
        XCTAssertThrowsError(try missing.rotateDescendants(.frontClockwise)) {
            XCTAssertEqual($0 as? EditorError, .unavailableOrigin)
        }
        var readonly = try EditorState(document: document(pivotFlags: "locked='true'"))
        try readonly.select("pivot")
        XCTAssertFalse(readonly.snapshot.canRotateDescendants)
        XCTAssertThrowsError(try readonly.rotateDescendants(.frontClockwise)) {
            XCTAssertEqual($0 as? EditorError, .readOnlyNode)
        }
        let large = try original.applying(
            .setNodes([
                .init(id: "pivot", value: .init(position: .init(x: 1_000_000, y: 1_000_000, z: 1), radius: 0.2)),
                .init(id: "child", value: .init(position: .init(x: -1_000_000, y: -1_000_000, z: 2), radius: 0.3)),
            ]))
        for locked in [false, true] {
            var state = try EditorState(document: large)
            try state.select("pivot")
            state.setLock(.x, isLocked: locked)
            XCTAssertThrowsError(try state.rotateDescendants(.frontClockwise)) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), large.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }
    func testActorRotationIsUndoableAndDoesNotAffectAnotherWindow() async throws {
        let original = try document()
        let session = EditorSession()
        let other = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await other.open(data: original.encoded())
        _ = try await session.select("pivot")
        _ = try await other.select("parent")
        let rotated = try await session.rotateDescendants(.sideClockwise)
        XCTAssertEqual(try rotated.document.node(id: "child").position, .init(x: 2, y: 2, z: 0))
        let unchanged = try await other.apply([])
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertEqual(unchanged.selectedID, "parent")
        XCTAssertFalse(unchanged.canUndo)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
        XCTAssertFalse(restored.canUndo)
        XCTAssertEqual(restored.selectedID, "pivot")
        let absent = EditorSession()
        do {
            _ = try await absent.rotateDescendants(.frontClockwise)
            XCTFail()
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
    }

}
