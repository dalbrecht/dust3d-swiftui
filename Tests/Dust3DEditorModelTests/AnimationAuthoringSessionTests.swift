import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class AnimationAuthoringSessionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='A' type='future' opaque='keep'/></animations><future value='retained'/></canvas>"
                    .utf8))
    }

    func testCreationCapturesSourceIgnoresSelectionAndPreservesExactHistory() async throws {
        let session = EditorSession()
        let original = try document()
        _ = try await session.open(data: original.encoded())
        let source = try await session.animationSnapshot()
        let target = try AnimationCreationTarget(snapshot: source)
        _ = try await session.selectAnimation("a")
        _ = try await session.setLock(.x, isLocked: true)
        let created = try await session.createAnimation(
            name: "  New  ", type: "BipedIdle",
            parameters: [
                DocumentAnimationParameter(name: "durationSeconds", value: "1.250"),
                DocumentAnimationParameter(name: "frameCount", value: "30"),
            ], target: target)
        let selected = try XCTUnwrap(created.list.selectedRow)
        XCTAssertNotEqual(selected.source.id, "a")
        XCTAssertEqual(selected.source.name, "  New  ")
        XCTAssertEqual(selected.source.type, "BipedIdle")
        XCTAssertEqual(selected.source.parameter(named: "durationSeconds"), "1.250")
        XCTAssertEqual(selected.source.parameter(named: "frameCount"), "30")
        XCTAssertEqual(created.list.rows.count, 2)
        XCTAssertEqual(created.list.rows.first?.source.parameter(named: "opaque"), "keep")
        XCTAssertFalse(target.isCurrent(in: created.editor))
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        XCTAssertTrue(undone.canRedo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), created.editor.document.encoded())
    }

    func testInvalidInitialParametersCannotPartiallyCreateARecordOrClearRedo() async throws {
        let session = EditorSession()
        let original = try document()
        _ = try await session.open(data: original.encoded())
        _ = try await session.apply([.setAnimationName(id: "a", name: "temporary")])
        _ = try await session.undo()
        let source = try await session.animationSnapshot()
        let target = try AnimationCreationTarget(snapshot: source)
        do {
            _ = try await session.createAnimation(
                name: "New", type: "BipedIdle",
                parameters: [
                    DocumentAnimationParameter(name: "durationSeconds", value: "1.250"),
                    DocumentAnimationParameter(name: "bad:name", value: "2"),
                ], target: target)
            XCTFail("An invalid later initial parameter must roll back creation")
        } catch { XCTAssertEqual(error as? DocumentAnimationError, .invalidParameter) }
        let unchanged = try await session.animationSnapshot()
        XCTAssertEqual(unchanged.editor.document.encoded(), original.encoded())
        XCTAssertEqual(unchanged.editor.documentRevision, source.editor.documentRevision)
        XCTAssertTrue(unchanged.editor.canRedo)
        XCTAssertNil(unchanged.list.selectedRow)
    }

    func testCreationRejectsChangedReopenedUnloadedAndInvalidCatalogSources() async throws {
        let session = EditorSession()
        let original = try document()
        _ = try await session.open(data: original.encoded())
        let source = try await session.animationSnapshot()
        let target = try AnimationCreationTarget(snapshot: source)
        _ = try await session.apply([.setAnimationName(id: "a", name: "temporary")])
        _ = try await session.undo()
        do {
            _ = try await session.createAnimation(name: "stale", type: "BipedIdle", target: target)
            XCTFail("Undo cannot revive a creation intent")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let unchanged = try await session.animationSnapshot()
        XCTAssertEqual(unchanged.editor.document.encoded(), original.encoded())
        XCTAssertTrue(unchanged.editor.canRedo)
        _ = try await session.open(data: original.encoded())
        do {
            _ = try await session.createAnimation(name: "stale", type: "BipedIdle", target: target)
            XCTFail("Identical replacement bytes have a different source identity")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let unloaded = EditorSession()
        do {
            _ = try await unloaded.createAnimation(name: "stale", type: "BipedIdle", target: target)
            XCTFail("Unloaded session cannot accept foreign creation")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        let invalid = try Dust3DDocument(
            snapshotXML: Data("<canvas><animations><animation id='a'/><animation id='a'/></animations></canvas>".utf8))
        _ = try await session.open(data: invalid.encoded())
        let failed = try await session.animationSnapshot()
        XCTAssertThrowsError(try AnimationCreationTarget(snapshot: failed)) {
            XCTAssertEqual($0 as? DocumentAnimationError, .duplicateIdentity("a"))
        }
    }

    func testParameterDraftCommitsOneUndoStepAndPreservesUnrelatedIntent() async throws {
        let session = EditorSession()
        let original = try document()
        _ = try await session.open(data: original.encoded())
        let source = try await session.selectAnimation("a")
        let target = try AnimationEditTarget(snapshot: source, animationID: "a")
        _ = try await session.selectAnimation(nil)
        let edited = try await session.editAnimation(
            [
                .setType("BipedIdle"), .setParameter(name: "durationSeconds", value: "1.250"),
                .setParameter(name: "frameCount", value: "30"),
                .setParameter(name: "breathingAmplitudeFactor", value: "0.65"),
            ], target: target)
        XCTAssertNil(edited.list.selectedRow)
        let record = try XCTUnwrap(edited.list.rows.first?.source)
        XCTAssertEqual(record.type, "BipedIdle")
        XCTAssertEqual(record.parameter(named: "durationSeconds"), "1.250")
        XCTAssertEqual(record.parameter(named: "frameCount"), "30")
        XCTAssertEqual(record.parameter(named: "opaque"), "keep")
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), edited.editor.document.encoded())
    }

    func testInvalidEmptyAndNetZeroDraftsPreserveBytesRevisionAndRedo() async throws {
        let session = EditorSession()
        let original = try document()
        _ = try await session.open(data: original.encoded())
        _ = try await session.apply([.setAnimationName(id: "a", name: "temporary")])
        _ = try await session.undo()
        let source = try await session.animationSnapshot()
        let target = try AnimationEditTarget(snapshot: source, animationID: "a")
        do {
            _ = try await session.editAnimation(
                [
                    .setType("BipedIdle"), .setParameter(name: "bad:name", value: "1"),
                ], target: target)
            XCTFail("A later invalid parameter must roll back the whole draft")
        } catch { XCTAssertEqual(error as? DocumentAnimationError, .invalidParameter) }
        for edits: [AnimationEdit] in [[], [.setType("temporary"), .setType("future")]] {
            let unchanged = try await session.editAnimation(edits, target: target)
            XCTAssertEqual(unchanged.editor.document.encoded(), original.encoded())
            XCTAssertEqual(unchanged.editor.documentRevision, source.editor.documentRevision)
            XCTAssertTrue(unchanged.editor.canRedo)
        }
    }
}
