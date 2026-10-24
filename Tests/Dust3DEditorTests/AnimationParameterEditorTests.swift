import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct ParameterEditorNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor
final class AnimationParameterEditorTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='Rest' type='future' gain=''/></animations></canvas>".utf8))
    }
    private func apply(_ edit: AnimationEdit, target: AnimationEditTarget, store: EditorStore) async -> Bool {
        await withCheckedContinuation { continuation in
            store.editAnimation(edit, target: target, completion: { continuation.resume(returning: $0) })
        }
    }
    private func target(_ store: EditorStore) async throws -> AnimationEditTarget {
        store.refreshAnimations()
        await store.animationQuery?.value
        return try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: "a")
    }
    func testDuplicateAdditionRetainsOriginalCauseAndAllowsCorrectedDraftOnSameTarget() async throws {
        let source = try source()
        let store = EditorStore(preview: ParameterEditorNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        let target = try await target(store)
        let generation = store.previewRevision
        let rejected = await apply(.addParameter(name: "gain", value: "replace"), target: target, store: store)
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.errorMessage, DocumentAnimationError.parameterAlreadyExists("gain").localizedDescription)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        let accepted = await apply(.addParameter(name: "newValue", value: "cafe\u{301}"), target: target, store: store)
        XCTAssertTrue(accepted)
        await store.animationQuery?.value
        let row = try XCTUnwrap(store.snapshot?.document.animations().first)
        XCTAssertTrue(try XCTUnwrap(row.parameter(named: "newValue")).utf8.elementsEqual("cafe\u{301}".utf8))
        XCTAssertEqual(row.parameter(named: "gain"), "")
        XCTAssertEqual(store.previewRevision, generation)
        XCTAssertTrue(store.canUndo)
        XCTAssertNil(store.errorMessage)
    }
    func testCapturedParameterAdditionRejectsReopenAndEditUndoEpochs() async throws {
        let session = EditorSession()
        let source = try source()
        _ = try await session.open(data: source.encoded())
        let snapshot = try await session.animationSnapshot()
        let target = try AnimationEditTarget(snapshot: snapshot, animationID: "a")
        _ = try await session.editAnimation(.rename("Temporary"), target: target)
        _ = try await session.undo()
        do {
            _ = try await session.editAnimation(.addParameter(name: "newValue", value: "1"), target: target)
            XCTFail("Undo must not revive an old parameter draft")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let after = try await session.animationSnapshot()
        XCTAssertEqual(after.editor.document.encoded(), source.encoded())
        XCTAssertTrue(after.editor.canRedo)
        _ = try await session.open(data: source.encoded())
        do {
            _ = try await session.editAnimation(.addParameter(name: "newValue", value: "1"), target: target)
            XCTFail("Reopen must retire an old parameter draft")
        } catch { XCTAssertEqual(error as? EditorError, .staleAnimationTarget) }
        let reopened = try await session.animationSnapshot()
        XCTAssertEqual(reopened.editor.document.encoded(), source.encoded())
        XCTAssertFalse(reopened.editor.canUndo)
    }
    func testOwnedAddParameterFormsRenderCurrentEmptyAndStaleStatesWithoutPublication() async throws {
        let store = EditorStore(preview: ParameterEditorNoPreview())
        defer { store.stop() }
        let data = try source().encoded()
        await store.load(data: data)
        let target = try await target(store)
        let directory = URL(
            fileURLWithPath:
                ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("ui-review/animation-parameter-addition", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        for (label, name, scheme, replaces) in [
            ("empty", "", ColorScheme.light, false),
            ("ready-light", "durationSeconds", .light, false),
            ("ready-dark", "durationSeconds", .dark, false),
            ("stale", "durationSeconds", .light, true),
        ] {
            if replaces { await store.load(data: data) }
            let png = try InspectorRenderer.png(
                AnimationParameterEditor(
                    store: store, target: target, name: AnimationNameText(name), value: AnimationNameText("1.00"),
                    onCancel: {}), width: 250, scheme: scheme)
            try png.write(to: directory.appendingPathComponent("\(label).png"))
            XCTAssertEqual(store.snapshot?.document.encoded(), data)
            XCTAssertEqual(publications, 0)
            XCTAssertFalse(store.canUndo)
        }
    }
}
