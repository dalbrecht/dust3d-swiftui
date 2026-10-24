import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class AnimationValueDraftTests: XCTestCase {
    func testStoredFieldMapsEmptyValueSeparatelyFromRemovalAndRetainsExactIdentity() {
        let field = AnimationStoredField.parameter("cafe\u{301}")
        if case .setParameter(let name, let value) = field.edit(value: "") {
            XCTAssertTrue(name.utf8.elementsEqual("cafe\u{301}".utf8))
            XCTAssertEqual(value, "")
        } else {
            XCTFail("Expected explicit empty parameter")
        }
        if case .setParameter(_, let value) = field.removal { XCTAssertNil(value) } else { XCTFail("Expected removal") }
        XCTAssertNil(AnimationStoredField.type.removal)
        if case .setType(let type) = AnimationStoredField.type.edit(value: "Future.Type") {
            XCTAssertEqual(type, "Future.Type")
        } else {
            XCTFail("Expected stored type")
        }
    }

    func testOpaqueQualifiedAndReservedParameterNamesStayReadOnly() {
        for name in [
            "ext:value", "xmlns", "id", "name", "type", "", "9value", "a b", String(repeating: "a", count: 129), "a!",
            "aé",
        ] {
            XCTAssertFalse(AnimationStoredField.parameter(name).isEditable, name)
        }
        for name in [
            "durationSeconds", "frameCount", "future-value", "future.value", "_value", "a9",
            String(repeating: "a", count: 128),
        ] {
            XCTAssertTrue(AnimationStoredField.parameter(name).isEditable, name)
        }
        XCTAssertTrue(AnimationStoredField.type.isEditable)
    }
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas xmlns:ext='urn:kept'><animations><animation id='a' name='Rest' type='future' gain='cafe&#x301;' ext:gain='opaque'><ext:child/></animation></animations></canvas>"
                    .utf8))
    }
    private func refreshed(_ store: EditorStore) async throws -> EditorAnimationSnapshot {
        store.refreshAnimations()
        await store.animationQuery?.value
        return try XCTUnwrap(store.animationSnapshot)
    }
    private func apply(_ edit: AnimationEdit, target: AnimationEditTarget, store: EditorStore) async -> Bool {
        await withCheckedContinuation { continuation in
            store.editAnimation(edit, target: target, completion: { continuation.resume(returning: $0) })
        }
    }
    private func settled(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingAnimations { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Metadata operation did not settle")
    }
    func testStoredValueEditsPreserveOpaqueDataAndExactHistoryThroughSaveReopen() async throws {
        let original = try source()
        let store = EditorStore(preview: AnimationValueNoPreview())
        defer { store.stop() }
        await store.load(data: original.encoded())
        let geometryRevision = store.previewRevision
        for (field, value) in [(AnimationStoredField.type, "Future.NewType"), (.parameter("gain"), "")] {
            let snapshot = try await refreshed(store)
            let target = try AnimationEditTarget(snapshot: snapshot, animationID: "a")
            let accepted = await apply(field.edit(value: value), target: target, store: store)
            XCTAssertTrue(accepted)
            try await settled(store)
        }
        let saved = try XCTUnwrap(store.snapshot?.document.encoded())
        let reopened = try Dust3DDocument(data: saved)
        let row = try XCTUnwrap(reopened.animations().first)
        XCTAssertEqual(row.type, "Future.NewType")
        XCTAssertEqual(row.parameter(named: "gain"), "")
        XCTAssertEqual(row.parameter(named: "ext:gain"), "opaque")
        XCTAssertTrue(String(decoding: reopened.modelXML, as: UTF8.self).contains("ext:child"))
        let snapshot = try await refreshed(store)
        let target = try AnimationEditTarget(snapshot: snapshot, animationID: "a")
        let removal = try XCTUnwrap(AnimationStoredField.parameter("gain").removal)
        let removed = await apply(removal, target: target, store: store)
        XCTAssertTrue(removed)
        try await settled(store)
        XCTAssertNil(try store.snapshot?.document.animations().first?.parameter(named: "gain"))
        store.undo()
        try await settled(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        store.undo()
        try await settled(store)
        store.undo()
        try await settled(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settled(store)
        store.redo()
        try await settled(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        XCTAssertEqual(store.previewRevision, geometryRevision)
    }
    func testRejectedAndReplacedSourceDoNotPublishCapturedValue() async throws {
        let original = try source()
        let store = EditorStore(preview: AnimationValueNoPreview())
        defer { store.stop() }
        await store.load(data: original.encoded())
        let snapshot = try await refreshed(store)
        let target = try AnimationEditTarget(snapshot: snapshot, animationID: "a")
        let rejected = await apply(.setType(""), target: target, store: store)
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        await store.load(data: original.encoded())
        let stale = await apply(.setParameter(name: "gain", value: "changed"), target: target, store: store)
        XCTAssertFalse(stale)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
    }
    func testOwnedStoredValueFormsRenderWithoutDocumentMutation() async throws {
        let store = EditorStore(preview: AnimationValueNoPreview())
        defer { store.stop() }
        await store.load(data: try source().encoded())
        let snapshot = try await refreshed(store)
        let target = try AnimationEditTarget(snapshot: snapshot, animationID: "a")
        let directory = URL(
            fileURLWithPath:
                ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("ui-review/animation-values", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let before = store.snapshot?.document.encoded()
        for (name, field, value) in [
            ("type", AnimationStoredField.type, "future"), ("parameter", .parameter("gain"), "cafe\u{301}"),
        ] {
            for scheme in [ColorScheme.light, .dark] {
                let draft = AnimationValueDraft(target: target, field: field, originalValue: value)
                let png = try InspectorRenderer.png(
                    AnimationValueEditor(store: store, draft: draft, onCancel: {}), width: 250, scheme: scheme)
                try png.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
                XCTAssertEqual(store.snapshot?.document.encoded(), before)
                XCTAssertFalse(store.canUndo)
            }
        }
    }

}

private struct AnimationValueNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}
