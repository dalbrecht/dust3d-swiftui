import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class AnimationEditTargetTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='A' type='future' retained='keep'/></animations></canvas>"
                    .utf8))
    }

    func testReopenAndEditUndoCannotReviveOldAnimationTargets() async throws {
        let session = EditorSession()
        let source = try document()
        _ = try await session.open(data: source.encoded())
        let selected = try await session.selectAnimation("a")
        let target = try AnimationEditTarget(snapshot: selected, animationID: "a")
        _ = try await session.apply([.setAnimationName(id: "a", name: "temporary")])
        _ = try await session.undo()
        let undone = try await session.animationSnapshot()
        XCTAssertEqual(undone.editor.document.encoded(), source.encoded())
        do {
            _ = try await session.editAnimation(.rename("stale"), target: target)
            XCTFail("Undo must not revive a captured target")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let unchanged = try await session.animationSnapshot()
        XCTAssertEqual(unchanged.editor.documentRevision, undone.editor.documentRevision)
        XCTAssertTrue(unchanged.editor.canRedo)
        _ = try await session.open(data: source.encoded())
        do {
            _ = try await session.duplicateAnimation(target: target, name: "stale copy")
            XCTFail("Reopen must invalidate a target despite identical bytes/IDs")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let reopened = try await session.animationSnapshot()
        XCTAssertEqual(reopened.list.rows.count, 1)
    }

    func testValidTargetsMapEveryEditAndIgnoreTransientSelectionAndLocks() async throws {
        let session = EditorSession()
        _ = try await session.open(data: document().encoded())
        let selected = try await session.selectAnimation("a")
        var target = try AnimationEditTarget(snapshot: selected, animationID: "a")
        _ = try await session.selectAnimation(nil)
        _ = try await session.setLock(.x, isLocked: true)
        let renamed = try await session.editAnimation(.rename("Renamed"), target: target)
        XCTAssertNil(renamed.list.selectedRow)
        XCTAssertEqual(renamed.list.rows.first?.title, "Renamed")
        target = try AnimationEditTarget(snapshot: renamed, animationID: "a")
        let typed = try await session.editAnimation(.setType("other"), target: target)
        target = try AnimationEditTarget(snapshot: typed, animationID: "a")
        let parameter = try await session.editAnimation(.setParameter(name: "duration", value: "2.50"), target: target)
        XCTAssertEqual(parameter.list.rows.first?.source.parameter(named: "duration"), "2.50")
        XCTAssertEqual(parameter.list.rows.first?.source.parameter(named: "retained"), "keep")
        target = try AnimationEditTarget(snapshot: parameter, animationID: "a")
        let copied = try await session.duplicateAnimation(target: target, name: "Copy")
        XCTAssertEqual(copied.list.rows.count, 2)
        let copyID = try XCTUnwrap(copied.list.selectedRow?.source.id)
        let copyTarget = try AnimationEditTarget(snapshot: copied, animationID: copyID)
        let deleted = try await session.editAnimation(.delete, target: copyTarget)
        XCTAssertEqual(deleted.list.rows.count, 1)
        XCTAssertNil(deleted.list.selectedRow)
    }

    func testTargetsRetainOriginalCatalogErrorsAndRejectUnknownOrUnloadedSources() async throws {
        let session = EditorSession()
        let bad = try Dust3DDocument(
            snapshotXML: Data("<canvas><animations><animation id='a'/><animation id='a'/></animations></canvas>".utf8))
        _ = try await session.open(data: bad.encoded())
        let invalid = try await session.animationSnapshot()
        XCTAssertThrowsError(try AnimationEditTarget(snapshot: invalid, animationID: "a")) {
            XCTAssertEqual($0 as? DocumentAnimationError, .duplicateIdentity("a"))
        }
        _ = try await session.open(data: document().encoded())
        let valid = try await session.animationSnapshot()
        XCTAssertThrowsError(try AnimationEditTarget(snapshot: valid, animationID: "missing")) {
            XCTAssertEqual($0 as? DocumentAnimationError, .missingAnimation("missing"))
        }
        let target = try AnimationEditTarget(snapshot: valid, animationID: "a")
        let unloaded = EditorSession()
        do {
            _ = try await unloaded.editAnimation(.delete, target: target)
            XCTFail("Unloaded editor must reject a foreign target")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
    }
}
