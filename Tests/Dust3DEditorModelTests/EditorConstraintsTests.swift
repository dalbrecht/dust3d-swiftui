import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EditorConstraintsTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='retain'><nodes><node id='a' partId='p' x='0' y='1' z='2' radius='0.1'/></nodes><parts><part id='p'/></parts></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='2'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let bytes =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model + Data([0, 255])
        return try Dust3DDocument(data: bytes)
    }

    func testLocksAreTransientAndIndependent() throws {
        let original = try document()
        var first = try EditorState(document: original)
        let second = try EditorState(document: original)
        for constraint in EditingConstraint.allCases { first.setLock(constraint, isLocked: true) }
        XCTAssertEqual(first.snapshot.locks, Set(EditingConstraint.allCases))
        XCTAssertTrue(second.snapshot.locks.isEmpty)
        XCTAssertEqual(first.snapshot.document.encoded(), original.encoded())
        XCTAssertEqual(first.snapshot.documentRevision, 0)
        XCTAssertFalse(first.snapshot.canUndo)
        for constraint in EditingConstraint.allCases { first.setLock(constraint, isLocked: false) }
        XCTAssertTrue(first.snapshot.locks.isEmpty)
        XCTAssertEqual(EditingConstraint.allCases.map(\.rawValue), ["X", "Y", "Z", "Radius"])
    }

    func testEveryLockCombinationRetainsOnlyUnlockedFieldsAndUndoBypassesLocks() throws {
        let original = try document()
        for mask in 0..<16 {
            var state = try EditorState(document: original)
            for (index, constraint) in EditingConstraint.allCases.enumerated() {
                state.setLock(constraint, isLocked: mask & (1 << index) != 0)
            }
            let locks = state.snapshot.locks
            try state.edit(id: "a", position: .init(x: 3, y: 4, z: 5), radius: 0.5)
            let expected = EditableNode(
                position: .init(
                    x: locks.contains(.x) ? 0 : 3, y: locks.contains(.y) ? 1 : 4, z: locks.contains(.z) ? 2 : 5),
                radius: locks.contains(.radius) ? 0.1 : 0.5)
            XCTAssertEqual(state.snapshot.selectedNode?.value, expected)
            XCTAssertEqual(state.snapshot.canUndo, mask != 15)
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertEqual(state.snapshot.locks, locks)
            try state.redo()
            XCTAssertEqual(state.snapshot.selectedNode?.value, expected)
            XCTAssertEqual(state.snapshot.document.asset(named: "opaque"), Data([0, 255]))
        }
    }

    func testBatchNodeCommandsHonorLocksAndRejectInvalidRequests() throws {
        var state = try EditorState(document: document())
        state.setLock(.x, isLocked: true)
        try state.apply([.setNode(id: "a", position: .init(x: 5, y: 6, z: 7), radius: 0.3)])
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: 0, y: 6, z: 7))
        let before = state.snapshot.document.encoded()
        XCTAssertThrowsError(try state.edit(id: "a", position: .init(x: .nan, y: 0, z: 0), radius: 0.1))
        XCTAssertThrowsError(try state.apply([.setNode(id: "missing", position: .init(x: 0, y: 0, z: 0), radius: 0.1)]))
        XCTAssertEqual(state.snapshot.document.encoded(), before)
    }

    @MainActor func testActorLocksArePerWindowAndDoNotDirtyDocuments() async throws {
        let first = EditorSession()
        let second = EditorSession()
        let original = try document().encoded()
        _ = try await first.open(data: original)
        _ = try await second.open(data: original)
        let locked = try await first.setLock(.radius, isLocked: true)
        XCTAssertEqual(locked.document.encoded(), original)
        XCTAssertEqual(locked.documentRevision, 0)
        let untouched = try await second.select("a")
        XCTAssertTrue(untouched.locks.isEmpty)
        let edited = try await first.edit(id: "a", position: .init(x: 1, y: 2, z: 3), radius: 0.9)
        XCTAssertEqual(try edited.document.node(id: "a").radius, 0.1)
    }

    func testProjectedDragPreservesLockedAxesInBothPlanes() throws {
        let original = try document().node(id: "a").position
        for plane in EditingPlane.allCases {
            let projection = CanvasProjection(bounds: CanvasBounds(nodes: []), plane: plane, width: 800, height: 600)
            let allLocked = projection.moving(original, by: .init(x: 40, y: 20), locks: Set(EditingConstraint.allCases))
            XCTAssertEqual(allLocked, original)
            let yLocked = projection.moving(original, by: .init(x: 40, y: 20), locks: [.y])
            XCTAssertEqual(yLocked.y, original.y)
            let horizontalLocked = projection.moving(original, by: .init(x: 40, y: 20), locks: [.x, .z])
            XCTAssertEqual(horizontalLocked.x, original.x)
            XCTAssertEqual(horizontalLocked.z, original.z)
            XCTAssertNotEqual(horizontalLocked.y, original.y)
        }
    }
}
