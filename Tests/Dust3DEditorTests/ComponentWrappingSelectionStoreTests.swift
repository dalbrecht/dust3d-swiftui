import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct MultiWrappingNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor final class ComponentWrappingSelectionStoreTests: XCTestCase {
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Batch wrapping did not settle")
    }
    func testCapturedActionsCannotRetargetAndCurrentBatchHasOneUndo() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a' wrap='Cloth'/><component id='b' wrap='Future'/></components></canvas>"
                    .utf8))
        let store = EditorStore(preview: MultiWrappingNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponents(["a", "b"])
        try await settle(store)
        let first = try XCTUnwrap(store.snapshot)
        let target = ComponentWrappingSelectionTarget(snapshot: first)
        let retained = store.componentWrappingSelectionAction(.mode(.skin), target: target)
        store.selectComponents(["a"])
        try await settle(store)
        store.selectComponents(["a", "b"])
        try await settle(store)
        retained()
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        let current = try XCTUnwrap(store.snapshot)
        store.componentWrappingSelectionAction(.scalar(.drape, 0.4), target: .init(snapshot: current))()
        try await settle(store)
        XCTAssertTrue(
            store.snapshot?.componentTree.rows.allSatisfy { $0.component.wrapping.scalarValue(.drape) == 0.4 } == true)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.snapshot?.canUndo == true)
    }
    func testMixedInkDraftCancelRetainedCallbackAndSingleUndo() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components>
                  <component id='a' wrap='Skin' wrapPatternColor='#123456'/>
                  <component id='b' wrap='Cloth' wrapPatternColor='#654321'/>
                </components></canvas>
                """.utf8))
        let store = EditorStore(preview: MultiWrappingNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponents(["a", "b"])
        try await settle(store)
        let selected = try XCTUnwrap(store.snapshot)
        let ink = ComponentWrappingSelectionPresentation(snapshot: selected).ink
        XCTAssertEqual(ink, .mixed)
        let draft = SurfaceInkDraft(selection: ink)
        XCTAssertFalse(draft.canApply)

        let target = ComponentWrappingSelectionTarget(snapshot: selected)
        let choose = draft.choosingAction { store.canEditComponentWrappingSelection(target) }
        let replacement = DocumentColor(red: 10, green: 20, blue: 30)
        choose(replacement)
        XCTAssertTrue(draft.canApply)
        draft.cancel(selection: ink)
        choose(replacement)
        XCTAssertFalse(draft.canApply)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())

        let retained = draft.choosingAction { store.canEditComponentWrappingSelection(target) }
        let apply = store.componentWrappingSelectionAction(.surfaceInk(replacement), target: target)
        store.selectComponents(["a"])
        try await settle(store)
        store.selectComponents(["a", "b"])
        try await settle(store)
        retained(replacement)
        apply()
        XCTAssertFalse(draft.canApply)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())

        let current = try XCTUnwrap(store.snapshot)
        let currentTarget = ComponentWrappingSelectionTarget(snapshot: current)
        draft.choosingAction { store.canEditComponentWrappingSelection(currentTarget) }(replacement)
        let color = try XCTUnwrap(draft.color.parsedColor)
        store.componentWrappingSelectionAction(.surfaceInk(color), target: currentTarget)()
        try await settle(store)
        let changed = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(ComponentWrappingSelectionPresentation(snapshot: changed).ink, .uniform(.value(replacement)))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.snapshot?.canUndo == true)
    }

    func testStoppedStoreRejectsRetainedValidAndInvalidNumericCallbacksWithoutErrors() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a'/><component id='b'/></components></canvas>"
                    .utf8))
        let store = EditorStore(preview: MultiWrappingNoPreview())
        await store.load(data: source.encoded())
        store.selectComponents(["a", "b"])
        try await settle(store)
        let target = ComponentWrappingSelectionTarget(snapshot: try XCTUnwrap(store.snapshot))
        let action = store.componentWrappingSelectionAction(.mode(.cloth), target: target)
        let number = store.componentWrappingSelectionNumberAction(target: target) {
            Double($0).map { .scalar(.drape, $0) }
        }
        store.stop()
        let before = store.snapshot?.document.encoded()
        let issue = store.errorMessage
        XCTAssertFalse(store.canEditComponentWrappingSelection(target))
        action()
        number("0.3")
        number("invalid")
        XCTAssertEqual(store.snapshot?.document.encoded(), before)
        XCTAssertEqual(store.errorMessage, issue)
        XCTAssertFalse(store.isWorking)
    }

    func testMixedControlsRenderWithoutPublishingAndShowExplicitValues() async throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='a' wrap='Cloth'/><component id='b' wrap='Future' wrapPattern='future' wrapPatternColor='opaque'/></components></canvas>"
                    .utf8))
        let store = EditorStore(preview: MultiWrappingNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        store.selectComponents(["a", "b"])
        try await settle(store)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        for scheme in [ColorScheme.light, .dark] {
            let png = try InspectorRenderer.png(
                ComponentWrappingSelectionControls(store: store), width: 320, scheme: scheme)
            XCTAssertGreaterThan(png.count, 100)
            if let directory = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                try png.write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent(
                        "multi-wrapping-" + (scheme == .dark ? "dark" : "light") + ".png"))
            }
        }
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
    }

}
