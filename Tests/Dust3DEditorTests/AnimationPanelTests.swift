import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct AnimationPanelNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor
final class AnimationPanelTests: XCTestCase {
    func testExactNativeNameInputPreservesUtf8AndReturnEscapeIntent() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var text = AnimationNameText("caf\u{e9}")
        var submitted = 0
        var canceled = 0
        let owner = AnimationNameField(
            text: Binding(get: { text }, set: { text = $0 }),
            onSubmit: { submitted += 1 }, onCancel: { canceled += 1 })
        let coordinator = owner.makeCoordinator()
        let field = AnimationNameField.makeField(text.value)
        field.stringValue = "cafe\u{301}"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(text.value.utf8.elementsEqual("cafe\u{301}".utf8))
        coordinator.submit(field)
        XCTAssertEqual(submitted, 1)
        XCTAssertEqual(field.accessibilityLabel(), "Animation name")
        XCTAssertEqual(field.accessibilityIdentifier(), "animation-name")
        XCTAssertTrue(
            coordinator.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(canceled, 1)
        XCTAssertEqual(submitted, 1, "Escape must not commit")
        field.isEnabled = false
        coordinator.submit(field)
        XCTAssertEqual(submitted, 1)
    }

    func testNativeTextUndoRoutingDoesNotFallThroughToDocumentHistory() {
        var nativeCalls = 0
        var documentCalls = 0
        EditorCommandScope.routeUndo(
            hasNativeEditor: true, nativeAction: { nativeCalls += 1 }, documentAction: { documentCalls += 1 })
        XCTAssertEqual(nativeCalls, 1)
        XCTAssertEqual(documentCalls, 0)
        EditorCommandScope.routeUndo(
            hasNativeEditor: false, nativeAction: { nativeCalls += 1 }, documentAction: { documentCalls += 1 })
        XCTAssertEqual(nativeCalls, 1)
        XCTAssertEqual(documentCalls, 1)
    }

    func testNameCompletionReportsRejectionAndAcceptedPublicationSeparately() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='Rest' type='future'/></animations></canvas>".utf8))
        let store = EditorStore(preview: AnimationPanelNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.refreshAnimations()
        await store.animationQuery?.value
        let target = try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: "a")
        var accepted: Bool?
        store.editAnimation(.rename("bad\nname"), target: target, completion: { accepted = $0 })
        for _ in 0..<300 {
            if !store.isWorking { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(accepted, false)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.editAnimation(.rename("Rest renamed"), target: target, completion: { accepted = $0 })
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingAnimations { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(accepted, true)
        XCTAssertEqual(store.animationSnapshot?.list.rows.first?.title, "Rest renamed")
    }

    func testGraphShortcutsAreExcludedFromAnimationAndNativeTextFocus() {
        XCTAssertFalse(EditorCommandScope.allowsGraphShortcuts(animationFocus: true, nativeTextFocus: false))
        XCTAssertFalse(EditorCommandScope.allowsGraphShortcuts(animationFocus: false, nativeTextFocus: true))
        XCTAssertFalse(EditorCommandScope.allowsGraphShortcuts(animationFocus: true, nativeTextFocus: true))
        XCTAssertTrue(EditorCommandScope.allowsGraphShortcuts(animationFocus: false, nativeTextFocus: false))
    }

    func testPanelStatesRenderOffscreenWithoutMutatingDocument() async throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"]
                ?? (ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()) + "/ui-review"
        )
        .appendingPathComponent("animation-panel", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let documents: [(String, Data)] = [
            (
                "selected",
                try Dust3DDocument(
                    snapshotXML: Data(
                        "<canvas><animations><animation id='a' name='Rest' type='biped.idle' duration='1.00' samples='30'/><animation id='b' name='Walk cycle' type='biped.walk'/></animations></canvas>"
                            .utf8)
                ).encoded()
            ),
            ("empty", Dust3DDocument.emptyArchive()),
            (
                "unavailable",
                try Dust3DDocument(
                    snapshotXML: Data(
                        "<canvas><animations><animation id='a'/><animation id='a'/></animations></canvas>".utf8)
                ).encoded()
            ),
            (
                "long",
                try Dust3DDocument(
                    snapshotXML: Data(
                        "<canvas><animations><animation id='a' name='A retained animation with a long descriptive name' type='future.unknown.extended.animation.type' future='retained value'/></animations></canvas>"
                            .utf8)
                ).encoded()
            ),
        ]
        for (name, data) in documents {
            let store = EditorStore(preview: AnimationPanelNoPreview())
            defer { store.stop() }
            await store.load(data: data)
            store.refreshAnimations()
            await store.animationQuery?.value
            if name == "selected" || name == "long" {
                store.selectAnimation("a")
                await store.animationQuery?.value
            }
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            for scheme in [ColorScheme.light, .dark] {
                let png = try InspectorRenderer.png(
                    AnimationPanel(store: store), width: 250, scheme: scheme, padding: 0)
                let image = try XCTUnwrap(NSBitmapImageRep(data: png))
                XCTAssertGreaterThan(image.pixelsWide, 0)
                try png.write(
                    to: root.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"),
                    options: .atomic)
                XCTAssertEqual(store.snapshot?.document.encoded(), data)
                XCTAssertEqual(publications, 0)
                XCTAssertFalse(store.canUndo)
            }
        }
    }

    func testRenameDraftRenderingKeepsCapturedTargetAndCurrentDocument() async throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"]
                ?? (ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()) + "/ui-review"
        )
        .appendingPathComponent("animation-panel", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='Rest' type='biped.idle'/></animations></canvas>".utf8))
        let store = EditorStore(preview: AnimationPanelNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.refreshAnimations()
        await store.animationQuery?.value
        let target = try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: "a")
        for stale in [false, true] {
            if stale {
                store.setOrigin(x: "1", y: "2", z: "3")
                for _ in 0..<300 {
                    if !store.isWorking { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                store.refreshAnimations()
                await store.animationQuery?.value
            }
            let before = store.snapshot?.document.encoded()
            let png = try InspectorRenderer.png(
                AnimationPanel(store: store, nameTarget: target, name: AnimationNameText("Rest & movement")),
                width: 250, scheme: .light, padding: 0,
                inspect: { hosting in
                    @MainActor func nameField(in view: NSView) -> NSTextField? {
                        if let field = view as? NSTextField,
                            field.accessibilityIdentifier() == "animation-name"
                        {
                            return field
                        }
                        return view.subviews.compactMap { nameField(in: $0) }.first
                    }
                    let field = try XCTUnwrap(nameField(in: hosting))
                    XCTAssertGreaterThanOrEqual(field.bounds.height, 40, "Name input needs a desktop hit area")
                })
            try png.write(
                to: root.appendingPathComponent(stale ? "rename-stale.png" : "rename-current.png"), options: .atomic)
            XCTAssertEqual(store.snapshot?.document.encoded(), before)
        }
    }
}
