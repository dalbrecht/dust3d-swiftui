import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct AnimationCreationNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor
final class AnimationCreationEditorTests: XCTestCase {
    private func target(_ store: EditorStore) async throws -> AnimationCreationTarget {
        store.refreshAnimations()
        await store.animationQuery?.value
        return try AnimationCreationTarget(snapshot: XCTUnwrap(store.animationSnapshot))
    }
    private func create(_ store: EditorStore, target: AnimationCreationTarget, name: String, type: String) async -> Bool
    {
        await withCheckedContinuation { continuation in
            store.createAnimation(
                name: name, type: type, target: target, completion: { continuation.resume(returning: $0) })
        }
    }
    func testRejectedCreationCanRetryExactTextWithoutHistoryOrGeometryChanges() async throws {
        let source = Dust3DDocument.emptyArchive()
        let store = EditorStore(preview: AnimationCreationNoPreview())
        defer { store.stop() }
        await store.load(data: source)
        let target = try await target(store)
        let generation = store.previewRevision
        let rejected = await create(store, target: target, name: "cafe\u{301}", type: "")
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.errorMessage, DocumentAnimationError.invalidType.localizedDescription)
        let accepted = await create(store, target: target, name: "cafe\u{301}", type: "Future.Type")
        XCTAssertTrue(accepted)
        await store.animationQuery?.value
        let row = try XCTUnwrap(store.animationSnapshot?.list.selectedRow?.source)
        XCTAssertTrue(try XCTUnwrap(row.name).utf8.elementsEqual("cafe\u{301}".utf8))
        XCTAssertEqual(row.type, "Future.Type")
        XCTAssertEqual(store.previewRevision, generation)
        XCTAssertTrue(store.canUndo)
        let saved = store.snapshot?.document.encoded()
        let stale = await create(store, target: target, name: "again", type: "Future.Type")
        XCTAssertFalse(stale)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        XCTAssertEqual(store.animationSnapshot?.list.rows.count, 1)
    }
    func testFailedOpenDoesNotPromoteRetainedDocumentForCreation() async throws {
        let source = Dust3DDocument.emptyArchive()
        let store = EditorStore(preview: AnimationCreationNoPreview())
        defer { store.stop() }
        await store.load(data: source)
        let target = try await target(store)
        await store.load(data: Data("not an archive".utf8))
        let cause = store.errorMessage
        XCTAssertNotNil(cause)
        let accepted = await create(store, target: target, name: "wrong document", type: "future")
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertEqual(store.errorMessage, cause)
        XCTAssertFalse(store.canUndo)
    }
    func testOwnedCreationFormsRenderEmptyReadyAndStaleSourcesWithoutPublication() async throws {
        let store = EditorStore(preview: AnimationCreationNoPreview())
        defer { store.stop() }
        let source = Dust3DDocument.emptyArchive()
        await store.load(data: source)
        let target = try await target(store)
        let directory = URL(
            fileURLWithPath:
                ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("ui-review/animation-creation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        for (label, type, scheme, replaces) in [
            ("empty", "", ColorScheme.light, false),
            ("ready-light", "Future.Type", .light, false),
            ("ready-dark", "Future.Type", .dark, false),
            ("stale", "Future.Type", .light, true),
        ] {
            if replaces { await store.load(data: source) }
            let png = try InspectorRenderer.png(
                AnimationCreationEditor(
                    store: store, target: target, name: AnimationNameText("Rest"), type: AnimationNameText(type),
                    onCancel: {}), width: 250, scheme: scheme)
            try png.write(to: directory.appendingPathComponent("\(label).png"))
            XCTAssertEqual(store.snapshot?.document.encoded(), source)
            XCTAssertEqual(publications, 0)
            XCTAssertFalse(store.canUndo)
        }
    }
}
