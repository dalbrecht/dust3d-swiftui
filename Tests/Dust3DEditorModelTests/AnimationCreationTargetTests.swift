import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class AnimationCreationTargetTests: XCTestCase {
    func testTargetedCreationSelectsFreshRecordAndPreservesHistoryAndReopen() async throws {
        let source = try Dust3DDocument(snapshotXML: Data("<canvas future='keep'><opaque/></canvas>".utf8))
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.animationSnapshot()
        let target = try AnimationCreationTarget(snapshot: before)
        let created = try await session.createAnimation(name: "Rest & breathe", type: "future", target: target)
        let first = try XCTUnwrap(created.list.selectedRow?.source)
        XCTAssertTrue(first.id.hasPrefix("{") && first.id.hasSuffix("}"))
        XCTAssertEqual(first.id.utf8.count, 38)
        XCTAssertNotNil(UUID(uuidString: String(first.id.dropFirst().dropLast())))
        XCTAssertEqual(first.name, "Rest & breathe")
        XCTAssertEqual(first.type, "future")
        XCTAssertTrue(String(decoding: created.editor.document.modelXML, as: UTF8.self).contains("opaque"))
        XCTAssertTrue(created.editor.canUndo)
        let saved = created.editor.document.encoded()
        XCTAssertEqual(try Dust3DDocument(data: saved).animations(), [first])
        _ = try await session.undo()
        let undone = try await session.animationSnapshot()
        XCTAssertEqual(undone.editor.document.encoded(), source.encoded())
        _ = try await session.redo()
        let redone = try await session.animationSnapshot()
        XCTAssertEqual(redone.editor.document.encoded(), saved)
        let second = try await session.createAnimation(
            name: "Rest & breathe", type: "future", target: AnimationCreationTarget(snapshot: redone))
        XCTAssertEqual(second.list.rows.count, 2)
        XCTAssertNotEqual(second.list.selectedRow?.source.id, first.id)
    }
    func testReopenAndEditUndoRetireCreationDraftBeforeAnyInsertion() async throws {
        let session = EditorSession()
        let source = Dust3DDocument.emptyArchive()
        _ = try await session.open(data: source)
        let snapshot = try await session.animationSnapshot()
        let target = try AnimationCreationTarget(snapshot: snapshot)
        _ = try await session.apply([.setOrigin(NodePosition(x: 1, y: 2, z: 3))])
        _ = try await session.undo()
        do {
            _ = try await session.createAnimation(name: "stale", type: "future", target: target)
            XCTFail("Edit/Undo must retire a creation target")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let unchanged = try await session.animationSnapshot()
        XCTAssertEqual(unchanged.editor.document.encoded(), source)
        XCTAssertTrue(unchanged.editor.canRedo)
        _ = try await session.open(data: source)
        do {
            _ = try await session.createAnimation(name: "stale", type: "future", target: target)
            XCTFail("Reopen must retire a creation target")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let reopened = try await session.animationSnapshot()
        XCTAssertEqual(reopened.editor.document.encoded(), source)
        XCTAssertFalse(reopened.editor.canUndo)
    }
    func testAmbiguousCatalogAndUnloadedSessionRejectCreationTarget() async throws {
        let session = EditorSession()
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        let snapshot = try await session.animationSnapshot()
        let target = try AnimationCreationTarget(snapshot: snapshot)
        let unloaded = EditorSession()
        do {
            _ = try await unloaded.createAnimation(name: "Rest", type: "future", target: target)
            XCTFail("Unloaded editor must reject")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        let ambiguous = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a'/><animation id='a'/></animations></canvas>".utf8))
        _ = try await session.open(data: ambiguous.encoded())
        let invalid = try await session.animationSnapshot()
        XCTAssertThrowsError(try AnimationCreationTarget(snapshot: invalid)) {
            XCTAssertEqual($0 as? DocumentAnimationError, .duplicateIdentity("a"))
        }
    }
}
