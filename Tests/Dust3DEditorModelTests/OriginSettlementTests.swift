import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class OriginSettlementTests: XCTestCase {
    private func archive(origin: String = "originX='9' originY='8' originZ='7'") -> Data {
        let model = Data(
            "<canvas \(origin) future='keep'><nodes><node id='a' partId='p' x='-2' y='3' z='1' radius='.5'/><node id='b' partId='q' x='4' y='-1' z='5' radius='1.5'/></nodes><parts><part id='p' locked='true'/><part id='q' visible='false' disabled='true'/></parts></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
    }

    func testRadiusBoundsIncludeEveryPartAndIgnoreSelectionWithExactHistory() async throws {
        let data = archive()
        let session = EditorSession()
        let original = try await session.open(data: data)
        _ = try await session.select("a")
        let centered = try await session.centerOriginOnModel()
        XCTAssertEqual(centered.origin, .init(x: 1.5, y: 0.5, z: 3.5))
        XCTAssertEqual(centered.nodes, original.nodes)
        XCTAssertEqual(centered.parts, original.parts)
        XCTAssertEqual(centered.selectedID, "a")
        let reopened = try Dust3DDocument(data: centered.document.encoded())
        XCTAssertEqual(try reopened.origin(), centered.origin)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), data)
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), centered.document.encoded())
        let noop = try await session.centerOriginOnModel()
        XCTAssertEqual(noop.documentRevision, redone.documentRevision)
        let undoneAgain = try await session.undo()
        XCTAssertEqual(undoneAgain.document.encoded(), data)
    }

    func testEveryLockUnavailableInitializationEmptyAndNoopPreserveRedo() throws {
        for locks: Set<EditingConstraint> in [[], [.x], [.y], [.z], [.radius], [.x, .y, .z]] {
            var state = try EditorState(document: Dust3DDocument(data: archive()))
            for lock in locks { state.setLock(lock, isLocked: true) }
            try state.centerOriginOnModel()
            XCTAssertEqual(
                state.snapshot.origin,
                .init(x: locks.contains(.x) ? 9 : 1.5, y: locks.contains(.y) ? 8 : 0.5, z: locks.contains(.z) ? 7 : 3.5)
            )
            var unavailable = try EditorState(document: Dust3DDocument(data: archive(origin: "originX='unsupported'")))
            for lock in locks { unavailable.setLock(lock, isLocked: true) }
            if locks.isDisjoint(with: [.x, .y, .z]) {
                try unavailable.centerOriginOnModel()
                XCTAssertEqual(unavailable.snapshot.origin, .init(x: 1.5, y: 0.5, z: 3.5))
            } else {
                let before = unavailable.snapshot.document.encoded()
                XCTAssertThrowsError(try unavailable.centerOriginOnModel()) {
                    XCTAssertEqual($0 as? EditorError, .unavailableOrigin)
                }
                XCTAssertEqual(unavailable.snapshot.document.encoded(), before)
                XCTAssertFalse(unavailable.snapshot.canUndo)
            }
        }
        var empty = try EditorState(document: Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        try empty.centerOriginOnModel()
        XCTAssertEqual(empty.snapshot.origin, .init(x: 0, y: 0, z: 0))
        let zero = empty.snapshot.document.encoded()
        try empty.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
        try empty.undo()
        XCTAssertTrue(empty.snapshot.canRedo)
        try empty.centerOriginOnModel()
        XCTAssertTrue(empty.snapshot.canRedo)
        XCTAssertEqual(empty.snapshot.document.encoded(), zero)
    }

    func testNumericBoundaryRejectsInvalidGeometryAndAcceptsExtremeValidBounds() throws {
        XCTAssertEqual(try OriginSettlement.center(of: []), .init(x: 0, y: 0, z: 0))
        let extreme = EditableNode(position: .init(x: 1_000_000, y: -1_000_000, z: 0), radius: 1_000_000)
        XCTAssertEqual(try OriginSettlement.center(of: [extreme]), extreme.position)
        for node in [
            EditableNode(position: .init(x: .nan, y: 0, z: 0), radius: 1),
            .init(position: .init(x: 0, y: .infinity, z: 0), radius: 1),
            .init(position: .init(x: 0, y: 0, z: 1_000_001), radius: 1),
            .init(position: .init(x: 0, y: 0, z: 0), radius: -1),
        ] {
            XCTAssertThrowsError(try OriginSettlement.center(of: [extreme, node])) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
        }
    }
}
