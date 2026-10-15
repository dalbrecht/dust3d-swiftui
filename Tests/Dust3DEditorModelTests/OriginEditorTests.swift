import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class OriginEditorTests: XCTestCase {
    private func document(origin: Bool = true) throws -> Dust3DDocument {
        let root = origin ? "originX='.25' originY='.75' originZ='1.5'" : ""
        let model = Data(
            "<canvas \(root)><nodes><node id='a' partId='p' x='.2' y='.3' z='.8' radius='.1'/><node id='b' partId='p' x='.6' y='.7' z='1.2' radius='.2'/><node id='c' partId='q' x='10' y='10' z='10' radius='.3'/></nodes><parts><part id='p'/><part id='q' locked='true'/></parts></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }
    func testOriginEditsHonorEveryAxisLockValidateBeforeMaskingAndUndoExactly() throws {
        let original = try document()
        for locks: Set<EditingConstraint> in [[], [.x], [.y], [.z], [.x, .y, .z], [.radius]] {
            var state = try EditorState(document: original)
            state.selectAll()
            for lock in locks { state.setLock(lock, isLocked: true) }
            try state.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
            XCTAssertEqual(
                state.snapshot.origin,
                .init(
                    x: locks.contains(.x) ? 0.25 : 1, y: locks.contains(.y) ? 0.75 : 2, z: locks.contains(.z) ? 1.5 : 3)
            )
            XCTAssertEqual(try state.snapshot.document.node(id: "a"), try original.node(id: "a"))
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c"])
            let before = state.snapshot.document.encoded()
            XCTAssertThrowsError(try state.apply([.setOrigin(.init(x: .nan, y: 0, z: 0))])) {
                XCTAssertEqual($0 as? DocumentError, .invalidOrigin)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), before)
        }
    }
    func testUnavailableOriginInitializationRequiresUnlockedAxesAndPreservesFailureState() throws {
        let original = try document(origin: false)
        for lock in [EditingConstraint.x, .y, .z] {
            var state = try EditorState(document: original)
            XCTAssertNil(state.snapshot.origin)
            state.setLock(lock, isLocked: true)
            XCTAssertThrowsError(try state.apply([.setOrigin(.init(x: 0, y: -1, z: 2))])) {
                XCTAssertEqual($0 as? EditorError, .unavailableOrigin)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
        var state = try EditorState(document: original)
        state.setLock(.radius, isLocked: true)
        try state.apply([.setOrigin(.init(x: 0, y: -1, z: 2))])
        XCTAssertEqual(state.snapshot.origin, .init(x: 0, y: -1, z: 2))
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
    }
    func testGlobalAlignmentUsesStoredOriginWithReadonlyNodesLocksAndExactUndo() throws {
        let original = try document()
        let cases: [(SelectionTransform, NodePosition)] = [
            (.originFrontX, .init(x: 0.25, y: 0.3, z: 0.8)),
            (.originFrontY, .init(x: 0.2, y: 0.75, z: 0.8)),
            (.originFrontCenter, .init(x: 0.25, y: 0.75, z: 0.8)),
            (.originSideZ, .init(x: 0.2, y: 0.3, z: 1.5)),
            (.originSideY, .init(x: 0.2, y: 0.75, z: 0.8)),
            (.originSideCenter, .init(x: 0.2, y: 0.75, z: 1.5)),
        ]
        for (transform, expected) in cases {
            XCTAssertTrue(transform.usesOrigin)
            var state = try EditorState(document: original)
            state.selectAll()
            try state.transformSelection(transform)
            XCTAssertEqual(try state.snapshot.document.node(id: "a").position, expected)
            XCTAssertEqual(try state.snapshot.document.node(id: "c"), try original.node(id: "c"))
            let edited = state.snapshot.document.encoded()
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            try state.redo()
            XCTAssertEqual(state.snapshot.document.encoded(), edited)
            state.setLock(.x, isLocked: true)
            state.setLock(.y, isLocked: true)
            state.setLock(.z, isLocked: true)
            try state.transformSelection(transform)
            XCTAssertEqual(state.snapshot.document.encoded(), edited)
        }
    }
    func testMissingOriginGlobalAlignmentRejectsAtomicallyWhileLocalStillWorks() throws {
        let original = try document(origin: false)
        var state = try EditorState(document: original)
        state.selectAll()
        XCTAssertThrowsError(try state.transformSelection(.originFrontX)) {
            XCTAssertEqual($0 as? EditorError, .unavailableOrigin)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
        XCTAssertEqual(state.snapshot.selectedIDs, ["a", "b", "c"])
        try state.transformSelection(.frontAlignX)
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position.x, 0.4, accuracy: 0.000001)
    }
    func testActorOriginBatchAndGlobalAlignmentAreSeparateUndoSteps() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        _ = try await session.selectAll()
        let origin = try await session.apply([.setOrigin(.init(x: 0, y: 0, z: 0))])
        XCTAssertEqual(origin.origin, .init(x: 0, y: 0, z: 0))
        let aligned = try await session.transformSelection(.originSideCenter)
        XCTAssertEqual(try aligned.document.node(id: "a").position, .init(x: 0.2, y: 0, z: 0))
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), origin.document.encoded())
        let originalAgain = try await session.undo()
        XCTAssertEqual(originalAgain.document.encoded(), original.encoded())
        XCTAssertFalse(originalAgain.canUndo)
    }
}
