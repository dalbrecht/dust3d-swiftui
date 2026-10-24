import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class AnimationBatchEditTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas custom='root'><animations vendor='x'><!--keep--><animation id='a' name='A' type='future' durationSeconds='1.125' frameCount='2' retained='keep'/><animation id='b' name='B' type='other'/></animations></canvas>"
                    .utf8))
    }

    func testBatchCommitsBothParametersWithExactSingleStepUndoAndLosslessReopen() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.animationSnapshot()
        let target = try AnimationEditTarget(snapshot: before, animationID: "a")
        let changed = try await session.editAnimations(
            [
                .setParameter(name: "durationSeconds", value: "2.500"),
                .setParameter(name: "frameCount", value: "3"),
            ], target: target)
        let row = try XCTUnwrap(changed.list.rows.first?.source)
        XCTAssertEqual(row.parameter(named: "durationSeconds"), "2.500")
        XCTAssertEqual(row.parameter(named: "frameCount"), "3")
        XCTAssertEqual(row.parameter(named: "retained"), "keep")
        XCTAssertEqual(changed.list.rows.last?.source, before.list.rows.last?.source)
        XCTAssertTrue(String(decoding: changed.editor.document.modelXML, as: UTF8.self).contains("<!--keep-->"))
        let reopened = try Dust3DDocument(data: changed.editor.document.encoded())
        XCTAssertEqual(reopened.modelXML, changed.editor.document.modelXML)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.editor.document.encoded())
    }

    func testInvalidLaterEditRejectsEntireBatchWithoutHistoryOrRevisionChange() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.animationSnapshot()
        let target = try AnimationEditTarget(snapshot: before, animationID: "a")
        do {
            _ = try await session.editAnimations(
                [
                    .rename("Changed"), .setParameter(name: "xmlns", value: "invalid"),
                ], target: target)
            XCTFail("Later invalid edit must reject the entire transaction")
        } catch { XCTAssertEqual(error as? DocumentAnimationError, .invalidParameter) }
        let after = try await session.animationSnapshot()
        XCTAssertEqual(after.editor.document.encoded(), original.encoded())
        XCTAssertEqual(after.editor.documentRevision, before.editor.documentRevision)
        XCTAssertFalse(after.editor.canUndo)
    }

    func testEmptyAndNetZeroBatchesPreserveRedoAndStaleTargetsReject() async throws {
        let session = EditorSession()
        _ = try await session.open(data: source().encoded())
        let initial = try await session.animationSnapshot()
        let old = try AnimationEditTarget(snapshot: initial, animationID: "a")
        _ = try await session.editAnimation(.rename("Temp"), target: old)
        _ = try await session.undo()
        let before = try await session.animationSnapshot()
        let target = try AnimationEditTarget(snapshot: before, animationID: "a")
        let empty = try await session.editAnimations([], target: target)
        XCTAssertEqual(empty.editor.documentRevision, before.editor.documentRevision)
        let netZero = try await session.editAnimations([.rename("Temp"), .rename("A")], target: target)
        XCTAssertEqual(netZero.editor.document.encoded(), before.editor.document.encoded())
        XCTAssertEqual(netZero.editor.documentRevision, before.editor.documentRevision)
        XCTAssertTrue(netZero.editor.canRedo)
        do {
            _ = try await session.editAnimations([.delete], target: old)
            XCTFail("Undo must not revive an old batch target")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
    }
}
