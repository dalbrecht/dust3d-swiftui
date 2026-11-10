import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor final class CanvasRadiusInputTests: XCTestCase {
    private let a = "{11111111-1111-4111-8111-111111111111}"
    private let b = "{22222222-2222-4222-8222-222222222222}"
    private let edge = "{44444444-4444-4444-8444-444444444444}"
    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        document = try document.applying(
            .addNode(
                id: a, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        document = try document.applying(
            .addNode(
                id: b, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", componentID: nil,
                position: .init(x: 1, y: 1, z: 1), radius: 0.3))
        return try document.applying(.addEdge(id: edge, from: a, to: b))
    }
    func testActualHeightControlsEqualDeltaPerWindowAndOneUndoWithFreshPreview() async throws {
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
        first.setCanvasHeight(100)
        second.setCanvasHeight(200)
        first.adjustSelectionRadius(direction: 1)
        first.setCanvasHeight(1000)
        second.adjustSelectionRadius(direction: 1)
        try await settle(first)
        try await settle(second)
        XCTAssertEqual(try XCTUnwrap(first.snapshot?.nodes.first { $0.id == a }?.value.radius), 0.11, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(first.snapshot?.nodes.first { $0.id == b }?.value.radius), 0.31, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(second.snapshot?.nodes.first { $0.id == a }?.value.radius), 0.105, accuracy: 1e-12)
        XCTAssertEqual(first.snapshot?.selectedEdgeIDs, [edge])
        XCTAssertNil(first.errorMessage)
        XCTAssertNotNil(first.mesh)
        XCTAssertFalse(first.previewState.isStale)
        first.undo()
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(first.canUndo)
        try render(second)
    }
    func testRadiusMenuRetainsItsWindowSelectionAndCanvasStep() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(a)
        try await settle(store)
        store.setCanvasHeight(100)

        var isInScope = true
        let retained = try XCTUnwrap(store.canvasRadiusAction(direction: 1) { isInScope })
        isInScope = false
        retained()
        try await settle(store)
        XCTAssertFalse(store.canUndo)

        isInScope = true
        store.select(b)
        try await settle(store)
        retained()
        try await settle(store)
        XCTAssertFalse(store.canUndo)

        let beforeResize = try XCTUnwrap(store.canvasRadiusAction(direction: 1) { isInScope })
        store.setCanvasHeight(200)
        beforeResize()
        try await settle(store)
        XCTAssertFalse(store.canUndo)

        let fresh = try XCTUnwrap(store.canvasRadiusAction(direction: 1) { isInScope })
        fresh()
        try await settle(store)
        let edited = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(try edited.document.node(id: a).radius, 0.1, accuracy: 1e-12)
        XCTAssertEqual(try edited.document.node(id: b).radius, 0.305, accuracy: 1e-12)
        XCTAssertTrue(store.canUndo)
    }

    func testRadiusMenuKeepsAddPreviewSeparateFromSelection() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(a)
        try await settle(store)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: store.plane, width: 400, height: 240),
            width: 400, height: 240)
        let selected = try XCTUnwrap(store.canvasRadiusAction(direction: 1) { true })
        store.beginAddMode()
        store.previewAddAtCanvasCenter()
        let initialRadius = store.addGhostRadius
        selected()
        XCTAssertEqual(store.addGhostRadius, initialRadius)

        let preview = try XCTUnwrap(store.canvasRadiusAction(direction: 1) { true })
        preview()
        XCTAssertEqual(store.addGhostRadius, initialRadius + 1)
        store.cancelAddMode()
        preview()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testWheelSelectionPrecedesHoverCommandScalesPositionsControlAdjustsRadiusAndUnsupportedPassesThrough()
        async throws
    {
        let source = try document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.setCanvasHeight(100)
        store.setHoveredNode(a)
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1, modifiers: .command)))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes.first { $0.id == a }?.value.radius), 0.11, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes.first { $0.id == b }?.value.radius), 0.3, accuracy: 1e-12)
        store.undo()
        try await settle(store)
        store.selectGraph(nodes: [b], edges: [])
        try await settle(store)
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 99, modifiers: .control)))
        try await settle(store)
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes.first { $0.id == b }?.value.radius), 0.31, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes.first { $0.id == a }?.value.radius), 0.1, accuracy: 1e-12)
        store.undo()
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1, modifiers: .command)))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.map(\.value.radius), [0.1, 0.3])
        XCTAssertEqual(
            try XCTUnwrap(store.snapshot?.nodes.first { $0.id == a }?.value.position.x), -0.005, accuracy: 1e-12)
        let bytes = store.snapshot?.document.encoded()
        XCTAssertFalse(store.handleCanvasWheel(.init(verticalDelta: 0)))
        XCTAssertFalse(store.handleCanvasWheel(.init(verticalDelta: 1, momentumPhase: .changed)))
        XCTAssertFalse(store.handleCanvasWheel(.init(verticalDelta: 1, phase: .ended)))
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        store.setCanvasHeight(0)
        XCTAssertFalse(store.canAdjustSelectionRadius)
    }
    func testHoverClearsOnPlaneDocumentHideAndExitAndRadiusLockBlocksInput() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.setCanvasHeight(100)
        store.setHoveredNode(a)
        store.plane = .side
        XCTAssertNil(store.hoveredNodeID)
        store.setHoveredNode(a)
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertNil(store.hoveredNodeID)
        store.setHoveredNode(a)
        store.clearCanvasHover()
        XCTAssertNil(store.hoveredNodeID)
        store.setHoveredNode(a)
        store.setPartState("{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", property: .visible, value: false)
        try await settle(store)
        XCTAssertNil(store.hoveredNodeID)
        store.setHoveredNode(a)
        XCTAssertNil(store.hoveredNodeID)
        store.undo()
        try await settle(store)
        store.select(a)
        try await settle(store)
        store.setHoveredNode(a)
        store.deleteNode()
        try await settle(store)
        XCTAssertNil(store.hoveredNodeID)
        store.undo()
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        store.setLock(.radius, isLocked: true)
        try await settle(store)
        XCTAssertFalse(store.canAdjustSelectionRadius)
        XCTAssertFalse(store.handleCanvasWheel(.init(verticalDelta: 1)))
    }
    func testNativeCanvasAndNodeWheelBoundariesRouteExactlyOnceAndKeyboardScopeExcludesText() {
        var calls = 0
        let canvas = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 120))
        canvas.enabled = true
        canvas.wheel = { _ in
            calls += 1
            return true
        }
        let node = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        node.enabled = true
        node.wheel = { _ in
            calls += 1
            return true
        }
        XCTAssertTrue(canvas.routeWheel(.init(verticalDelta: 1)))
        XCTAssertTrue(node.routeWheel(.init(verticalDelta: 1)))
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(EditorCommandScope.allowsGraphShortcuts(animationFocus: false, nativeTextFocus: true))
        XCTAssertFalse(EditorCommandScope.allowsGraphShortcuts(animationFocus: true, nativeTextFocus: false))
    }
    func testRadiusKeysRequireTheActualCanvasResponderAndLeaveOtherControlsAlone() throws {
        let window = CanvasKeyboardTestWindow(
            contentRect: .init(x: -10000, y: -10000, width: 400, height: 300),
            styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        let parent = NSView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let canvas = CanvasPointerView(frame: parent.bounds)
        let node = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        let text = NSTextView(frame: .init(x: 50, y: 50, width: 100, height: 30))
        parent.addSubview(canvas)
        parent.addSubview(node)
        parent.addSubview(text)
        window.contentView = parent
        canvas.enabled = true
        node.enabled = true
        var directions: [Int] = []
        canvas.radiusKey = {
            directions.append($0)
            return true
        }
        node.radiusKey = {
            directions.append($0)
            return true
        }
        func key(_ characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
        }
        XCTAssertTrue(window.makeFirstResponder(text))
        XCTAssertFalse(canvas.routeRadiusKey(try key("-")))
        XCTAssertFalse(node.routeRadiusKey(try key("=")))
        XCTAssertTrue(directions.isEmpty)
        XCTAssertTrue(window.makeFirstResponder(canvas))
        window.acceptsCanvasKeys = false
        XCTAssertFalse(canvas.routeRadiusKey(try key("-")))
        XCTAssertTrue(window.makeFirstResponder(node))
        XCTAssertFalse(node.routeRadiusKey(try key("=")))
        XCTAssertTrue(directions.isEmpty)
        window.acceptsCanvasKeys = true
        XCTAssertTrue(window.makeFirstResponder(canvas))
        XCTAssertTrue(canvas.routeRadiusKey(try key("-")))
        XCTAssertTrue(canvas.routeRadiusKey(try key("=")))
        XCTAssertFalse(node.routeRadiusKey(try key("=")))
        for modifier: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            XCTAssertFalse(canvas.routeRadiusKey(try key("=", modifiers: modifier)))
        }
        XCTAssertFalse(canvas.routeRadiusKey(try key("a")))
        canvas.enabled = false
        XCTAssertFalse(canvas.routeRadiusKey(try key("=")))
        XCTAssertTrue(window.makeFirstResponder(node))
        XCTAssertTrue(node.routeRadiusKey(try key("=")))
        XCTAssertTrue(window.makeFirstResponder(text))
        XCTAssertFalse(node.routeRadiusKey(try key("-")))
        XCTAssertTrue(window.makeFirstResponder(canvas))
        canvas.enabled = true
        canvas.keyDown(with: try key("-"))
        XCTAssertTrue(window.makeFirstResponder(node))
        node.keyDown(with: try key("="))
        XCTAssertEqual(directions, [-1, 1, 1, -1, 1])
    }

    func testNativeWheelDeliveryUsesOnlyHitResponderAndPassesUnhandledToParent() throws {
        let parent = RadiusWheelParent(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let canvas = CanvasPointerView(frame: parent.bounds)
        let node = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        parent.addSubview(canvas)
        parent.addSubview(node)
        canvas.enabled = true
        node.enabled = true
        var canvasCalls = 0
        var nodeCalls = 0
        canvas.wheel = { _ in
            canvasCalls += 1
            return true
        }
        node.wheel = { _ in
            nodeCalls += 1
            return true
        }
        let cg = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        node.scrollWheel(with: event)
        XCTAssertEqual(nodeCalls, 1)
        XCTAssertEqual(canvasCalls, 0)
        XCTAssertEqual(parent.passed, 0)
        canvas.scrollWheel(with: event)
        XCTAssertEqual(canvasCalls, 1)
        node.wheel = { _ in
            nodeCalls += 1
            return false
        }
        node.scrollWheel(with: event)
        XCTAssertEqual(nodeCalls, 2)
        XCTAssertEqual(canvasCalls, 1)
        XCTAssertEqual(parent.passed, 1)
    }
    func testNativeMarqueeRemovalCancelsGestureAndHover() throws {
        let canvas = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        canvas.enabled = true
        var taps = 0
        var clearedHover = false
        canvas.tap = { _, _ in taps += 1 }
        canvas.hover = { if $0 == nil { clearedHover = true } }
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .init(x: 10, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: .init(x: 10, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        canvas.mouseEntered(with: down)
        canvas.mouseDown(with: down)
        canvas.invalidate()
        canvas.mouseUp(with: up)
        XCTAssertEqual(taps, 0)
        XCTAssertTrue(clearedHover)
    }
    func testHostedCanvasCapturesActualHeightAndCancelsMarqueeOnFocusLossDisableAndRemoval() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let host = NSHostingView(rootView: NodeCanvas(store: store).frame(width: 400, height: 173))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.canvasHeight, 173)
        let canvas = try XCTUnwrap(findCanvas(in: host))
        canvas.enabled = true
        var publications = 0
        var hoverCleared = false
        canvas.tap = { _, _ in publications += 1 }
        canvas.select = { _, _ in publications += 1 }
        canvas.hover = { if $0 == nil { hoverCleared = true } }
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .init(x: 10, y: 20), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: .init(x: 50, y: 60), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        canvas.mouseEntered(with: down)
        canvas.mouseDown(with: down)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        canvas.mouseUp(with: up)
        XCTAssertEqual(publications, 0)
        XCTAssertTrue(hoverCleared)
        canvas.mouseDown(with: down)
        canvas.enabled = false
        canvas.enabled = true
        canvas.mouseUp(with: up)
        XCTAssertEqual(publications, 0)
        canvas.mouseDown(with: down)
        host.rootView = NodeCanvas(store: store).frame(width: 400, height: 233)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        canvas.mouseUp(with: up)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.canvasHeight, 233)
        XCTAssertFalse(try XCTUnwrap(findCanvas(in: host)) === canvas)
    }
    func testRepresentableCancellationDoesNotSynchronouslyMutateSwiftUIState() throws {
        let canvas = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: canvas.frame, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        window.contentView = canvas
        canvas.enabled = true
        var stateCallbacks = 0
        canvas.rectangle = { _ in stateCallbacks += 1 }
        canvas.hover = { _ in stateCallbacks += 1 }
        canvas.enabled = false
        canvas.cancelActivation()
        window.contentView = nil
        XCTAssertEqual(stateCallbacks, 0, "Native lifecycle cancellation leaves presentation clearing to SwiftUI hooks")
    }
    func testHostedCanvasRadiusKeyChangesOnlyAddGhostWhileAddingNodes() async throws {
        let source = try document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let host = NSHostingView(rootView: NodeCanvas(store: store).frame(width: 400, height: 240))
        let window = CanvasKeyboardTestWindow(
            contentRect: .init(x: -10000, y: -10000, width: 400, height: 240),
            styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        store.beginAddMode()
        XCTAssertTrue(store.isAddingNodes)
        store.previewAddAtCanvasCenter()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let canvas = try XCTUnwrap(findCanvas(in: host))
        XCTAssertTrue(window.makeFirstResponder(canvas))
        let radius = store.addGhostRadius
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "=",
                charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
        XCTAssertTrue(canvas.routeRadiusKey(event))
        XCTAssertEqual(store.addGhostRadius, radius + 1)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func findCanvas(in view: NSView) -> CanvasPointerView? {
        if let canvas = view as? CanvasPointerView { return canvas }
        return view.subviews.lazy.compactMap { self.findCanvas(in: $0) }.first
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<400 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Canvas adjustment did not settle")
    }
    private func render(_ store: EditorStore) throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("ui-qa/additive-radius")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let data = try InspectorRenderer.png(NodeRadiusAdjustmentControls(store: store), width: 300, scheme: scheme)
            try data.write(to: directory.appendingPathComponent("radius-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}

@MainActor private final class RadiusWheelParent: NSView {
    private(set) var passed = 0
    override func scrollWheel(with event: NSEvent) { passed += 1 }
}
