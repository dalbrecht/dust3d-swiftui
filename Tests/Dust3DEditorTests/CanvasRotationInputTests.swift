import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor final class CanvasRotationInputTests: XCTestCase {
    private let a = "{11111111-1111-4111-8111-111111111111}"
    private let b = "{22222222-2222-4222-8222-222222222222}"
    private let edge = "{44444444-4444-4444-8444-444444444444}"
    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        document = try document.applying(
            .addNode(
                id: a,
                partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        document = try document.applying(
            .addNode(
                id: b,
                partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", componentID: nil,
                position: .init(x: 1, y: 1, z: 1), radius: 0.3))
        document = try document.applying(.addEdge(id: edge, from: a, to: b))
        return try document.applying(.setOrigin(.init(x: 0, y: 0, z: 0)))
    }
    func testCapturedAnglePlaneAndWindowRoutingHaveOneUndoFreshPreviewAndRender() async throws {
        let source = try document()
        let first = EditorStore()
        let second = EditorStore()
        defer {
            first.stop()
            second.stop()
        }
        for store in [first, second] {
            await store.load(data: source.encoded())
            try await settle(store)
            store.selectGraph(nodes: [a], edges: [edge])
            try await settle(store)
        }
        first.plane = .side
        XCTAssertTrue(first.canRotateCanvasSelection)
        first.rotateCanvasSelection(degrees: 1)
        first.rotateCanvasSelection(degrees: 30)
        try await settle(first)
        let node = try XCTUnwrap(first.snapshot).document.node(id: b)
        XCTAssertEqual(node.position.y, 0.5 + 0.5 * (sin(.pi / 180) + cos(.pi / 180)), accuracy: 1e-12)
        XCTAssertEqual(node.position.z, 0.5 + 0.5 * (cos(.pi / 180) - sin(.pi / 180)), accuracy: 1e-12)
        XCTAssertEqual(second.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(first.snapshot?.selectedEdgeIDs, [edge])
        XCTAssertFalse(first.previewState.isStale)
        XCTAssertNotNil(first.mesh)
        first.undo()
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(first.canUndo)
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("ui-qa/fine-angle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            try InspectorRenderer.png(CanvasRotationControls(store: first), width: 330, scheme: scheme)
                .write(to: directory.appendingPathComponent("rotation-\(scheme == .light ? "light" : "dark").png"))
        }
        first.select(b)
        try await settle(first)
        for scheme in [ColorScheme.light, .dark] {
            try InspectorRenderer.png(
                NodeInspector(store: first).environment(EditorPasteboard()).frame(height: 1800),
                width: 330, scheme: scheme
            )
            .write(to: directory.appendingPathComponent("inspector-\(scheme == .light ? "light" : "dark").png"))
        }
    }
    func testRetainedActionRejectsSelectionLocksPlaneToolAndReplacementChanges() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        let selectionAction = store.canvasRotationAction(degrees: -1)
        store.select(a)
        try await settle(store)
        selectionAction()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        store.selectEdges([edge])
        try await settle(store)
        let lockAction = store.canvasRotationAction(degrees: 30)
        store.setLock(.x, isLocked: true)
        try await settle(store)
        lockAction()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        let beforePlaneChange = try XCTUnwrap(store.canvasRotationContext)
        let planeAction = store.canvasRotationAction(degrees: 30)
        store.plane = .side
        store.plane = beforePlaneChange.plane
        XCTAssertNotEqual(store.canvasRotationContext, beforePlaneChange)
        planeAction()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        let oldAction = store.canvasRotationAction(degrees: 30)
        await store.load(data: source.encoded())
        try await settle(store)
        oldAction()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        store.selectEdges([edge])
        try await settle(store)
        let originAction = store.canvasRotationAction(degrees: 1)
        store.setMovingOrigin(true)
        XCTAssertFalse(store.canRotateCanvasSelection)
        originAction()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        store.setMovingOrigin(false)
        store.setCanvasHeight(200)
        store.setCanvasContext(
            projection: CanvasProjection(bounds: store.bounds, plane: store.plane, width: 300, height: 200), width: 300,
            height: 200)
        store.beginAddMode()
        XCTAssertFalse(store.canRotateCanvasSelection)
        store.rotateCanvasSelection(degrees: 1)
        XCTAssertFalse(store.canUndo)
    }
    func testMenuShortcutRetainsItsTargetAndRechecksWindowAndModifiers() async throws {
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: try document().encoded())
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)

        var isInScope = true
        let retained = try XCTUnwrap(store.canvasRotationShortcutAction(characters: ".") { isInScope })
        isInScope = false
        retained([])
        try await settle(store)
        XCTAssertFalse(store.canUndo)

        isInScope = true
        retained(.shift)
        try await settle(store)
        XCTAssertFalse(store.canUndo)

        store.select(a)
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        retained([])
        try await settle(store)
        XCTAssertFalse(store.canUndo)

        let fresh = try XCTUnwrap(store.canvasRotationShortcutAction(characters: ".") { isInScope })
        fresh([])
        try await settle(store)
        XCTAssertTrue(store.canUndo)
    }

    func testBarePunctuationPolicyExcludesModifiersTextAndAnimation() {
        XCTAssertEqual(
            CanvasRotationInput.degrees(characters: ",", modifiers: [], animationFocus: false, nativeTextFocus: false),
            -1)
        XCTAssertEqual(
            CanvasRotationInput.degrees(characters: ".", modifiers: [], animationFocus: false, nativeTextFocus: false),
            1)
        for modifiers in [NSEvent.ModifierFlags.command, .control, .option, .shift] {
            XCTAssertNil(
                CanvasRotationInput.degrees(
                    characters: ".", modifiers: modifiers, animationFocus: false, nativeTextFocus: false))
        }
        XCTAssertNil(
            CanvasRotationInput.degrees(characters: ">", modifiers: [], animationFocus: false, nativeTextFocus: false))
        XCTAssertNil(
            CanvasRotationInput.degrees(characters: ".", modifiers: [], animationFocus: true, nativeTextFocus: false))
        XCTAssertNil(
            CanvasRotationInput.degrees(characters: ",", modifiers: [], animationFocus: false, nativeTextFocus: true))
    }
    func testGeneralAngleDraftRejectsIncompleteInvalidAndLocaleMismatchInsteadOfReusingLastAngle() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(CanvasRotationInput.angle(from: "17.5", locale: locale), 17.5)
        for text in ["", "-", "1x", "nan", "inf", "2147483648", "1.2.3"] {
            XCTAssertNil(CanvasRotationInput.angle(from: text, locale: locale))
        }
        XCTAssertEqual(CanvasRotationInput.angle(from: "17,5", locale: Locale(identifier: "de_DE")), 17.5)
    }
    func testNativeHostedAngleFieldReturnValidatesDisplayedDraft() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        let host = NSHostingView(rootView: CanvasRotationControls(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        let field = try XCTUnwrap(fields(host).first { $0.isEditable })
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
        let enter = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        editor.string = "invalid"
        editor.didChangeText()
        editor.keyDown(with: enter)
        await Task.yield()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(window.makeFirstResponder(field))
        let validEditor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
        validEditor.string = "17.5"
        validEditor.didChangeText()
        validEditor.keyDown(with: enter)
        await Task.yield()
        try await settle(store)
        let node = try XCTUnwrap(store.snapshot).document.node(id: b)
        let radians = 17.5 * Double.pi / 180
        XCTAssertEqual(node.position.y, 0.5 + 0.5 * (sin(radians) + cos(radians)), accuracy: 1e-12)
        XCTAssertTrue(store.canUndo)
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Rotation did not settle")
    }
}
