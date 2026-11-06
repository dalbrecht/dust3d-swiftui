import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor
@testable import Dust3DRendering

@MainActor final class PrecisionCanvasInputTests: XCTestCase {
    private let a = "{11111111-1111-4111-8111-111111111111}"
    private let b = "{22222222-2222-4222-8222-222222222222}"
    private let edge = "{44444444-4444-4444-8444-444444444444}"
    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        document = try document.applying(
            .addNode(
                id: a, partID: part,
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        document = try document.applying(
            .addNode(
                id: b, partID: part, componentID: nil,
                position: .init(x: 1, y: 1, z: 1), radius: 0.3))
        document = try document.applying(.addEdge(id: edge, from: a, to: b))
        return try document.applying(.setOrigin(.init(x: 0.5, y: 0.5, z: 0.5)))
    }
    func testActualHeightAndCapturedPlaneDriveMovementNotProjectionScaleAndEachEditUndoesOnce() async throws {
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
        second.plane = .side
        first.performCanvasPrecision(.right)
        first.setCanvasHeight(1000)  // An already accepted command keeps H=100.
        first.plane = .side  // It also keeps Front mapping.
        second.performCanvasPrecision(.right)
        try await settle(first)
        try await settle(second)
        XCTAssertEqual(try XCTUnwrap(first.snapshot).document.node(id: a).position, .init(x: 0.01, y: 0, z: 0))
        XCTAssertEqual(try XCTUnwrap(second.snapshot).document.node(id: a).position, .init(x: 0, y: 0, z: 0.005))
        XCTAssertEqual(first.snapshot?.selectedEdgeIDs, [edge])
        XCTAssertNotNil(first.mesh)
        XCTAssertFalse(first.previewState.isStale)
        first.undo()
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(first.canUndo)
    }
    func testSpacingScalesAllCoordinatesButNeverRadiiAndOriginArrowsPersistToolWithoutMovingGraph() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        store.setCanvasHeight(100)
        store.performCanvasPrecision(.increaseSpacing)
        try await settle(store)
        let node = try XCTUnwrap(store.snapshot).document.node(id: b)
        XCTAssertEqual(node.position.x, 1.05, accuracy: 1e-12)
        XCTAssertEqual(node.position.y, 1.05, accuracy: 1e-12)
        XCTAssertEqual(node.position.z, 1.05, accuracy: 1e-12)
        XCTAssertEqual(node.radius, 0.3)
        store.undo()
        try await settle(store)
        store.setMovingOrigin(true)
        store.performCanvasPrecision(.right)
        try await settle(store)
        XCTAssertTrue(store.isMovingOrigin)
        store.performCanvasPrecision(.down)
        try await settle(store)
        XCTAssertTrue(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.origin, .init(x: 0.51, y: 0.51, z: 0.5))
        for id in [a, b] {
            XCTAssertEqual(try XCTUnwrap(store.snapshot).document.node(id: id), try source.node(id: id))
        }
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edge])
        store.undo()
        try await settle(store)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
    }
    func testRetainedActionsRejectHeightPlaneSelectionAndToolAwayBackAndAddModeIsDisabled() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        store.setCanvasHeight(100)
        let old = store.canvasPrecisionAction(.left)
        store.setCanvasHeight(200)
        store.setCanvasHeight(100)
        old()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        let plane = store.canvasPrecisionAction(.left)
        store.plane = .side
        store.plane = .front
        plane()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        let selection = store.canvasPrecisionAction(.left)
        store.select(a)
        try await settle(store)
        selection()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        let tool = store.canvasPrecisionAction(.left)
        store.setMovingOrigin(true)
        store.setMovingOrigin(false)
        tool()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: store.plane, width: 400, height: 300), width: 400,
            height: 300)
        store.beginAddMode()
        XCTAssertFalse(store.canPerformCanvasPrecision(.left))
        XCTAssertFalse(store.canPerformCanvasPrecision(.increaseSpacing))
    }
    func testNativeCanvasAndNodeKeyBoundaryRequiresActualFirstResponderAndPassesUnsupportedKeys() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = root
        defer { window.contentView = nil }
        let canvas = CanvasPointerView(frame: root.bounds)
        canvas.enabled = true
        root.addSubview(canvas)
        let other = PrecisionOtherResponder(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        root.addSubview(other)
        var keys = 0
        canvas.precisionKey = { input in
            guard input.action != nil else { return false }
            keys += 1
            return true
        }
        XCTAssertTrue(window.makeFirstResponder(other))
        canvas.keyDown(with: try key(124, window: window))
        XCTAssertEqual(keys, 0)
        XCTAssertTrue(window.makeFirstResponder(canvas))
        canvas.keyDown(with: try key(124, window: window))
        XCTAssertEqual(keys, 1)
        canvas.keyDown(with: try key(124, window: window, modifiers: [.command]))
        XCTAssertEqual(keys, 1)
        canvas.removeFromSuperview()
        canvas.keyDown(with: try key(124, window: window))
        XCTAssertEqual(keys, 1)
        let node = NodePointerView(frame: root.bounds)
        node.enabled = true
        node.precisionKey = { _ in
            keys += 1
            return true
        }
        root.addSubview(node)
        XCTAssertTrue(window.makeFirstResponder(node))
        node.keyDown(with: try key(123, window: window))
        XCTAssertEqual(keys, 2)
    }
    func testKeyPolicyRecognizesBareArrowsAndActualBracketCharactersOnly() {
        XCTAssertEqual(CanvasPrecisionKeyInput(keyCode: 123, characters: "", modifiers: []).action, .left)
        XCTAssertEqual(CanvasPrecisionKeyInput(keyCode: 30, characters: "]", modifiers: []).action, .increaseSpacing)
        XCTAssertNil(CanvasPrecisionKeyInput(keyCode: 30, characters: "}", modifiers: [.shift]).action)
        for flags in [NSEvent.ModifierFlags.command, .control, .option, .shift] {
            XCTAssertNil(CanvasPrecisionKeyInput(keyCode: 124, characters: "", modifiers: flags).action)
        }
    }
    func testSpacingWithOriginActiveKeepsOriginAndToolAndExplicitLaterOffWins() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectEdges([edge])
        try await settle(store)
        store.setCanvasHeight(100)
        store.setMovingOrigin(true)
        XCTAssertTrue(store.canPerformCanvasPrecision(.increaseSpacing))
        store.performCanvasPrecision(.increaseSpacing)
        try await settle(store)
        XCTAssertTrue(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.origin, .init(x: 0.5, y: 0.5, z: 0.5))
        XCTAssertEqual(try XCTUnwrap(store.snapshot).document.node(id: b).position.z, 1.05, accuracy: 1e-12)
        store.performCanvasPrecision(.right)
        store.setMovingOrigin(false)
        try await settle(store)
        XCTAssertFalse(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.origin?.x, 0.51)
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("ui-qa/precision-input")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            try InspectorRenderer.png(CanvasPrecisionPanel(store: store), width: 330, scheme: scheme)
                .write(to: directory.appendingPathComponent("precision-\(scheme == .light ? "light" : "dark").png"))
        }
    }
    func testProductionCanvasNodeAndOriginClickGiveKeyboardFocusAndRealKeysEditTheirOwnTargets() async throws {
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: try document().encoded())
        try await settle(store)
        store.select(a)
        try await settle(store)
        let host = NSHostingView(rootView: NodeCanvas(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func nodes(_ view: NSView) -> [NodePointerView] {
            (view as? NodePointerView).map { [$0] } ?? view.subviews.flatMap(nodes)
        }
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if nodes(host).filter({ !$0.isRectangular && $0.precisionKey != nil }).count == 2 && store.canvasHeight > 0
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let node = try XCTUnwrap(
            nodes(host).filter { !$0.isRectangular && $0.precisionKey != nil }.min {
                $0.convert(.zero, to: host).x < $1.convert(.zero, to: host).x
            })
        try click(node, window: window)
        try await settle(store)
        XCTAssertTrue(window.firstResponder === node)
        node.keyDown(with: try key(124, window: window))
        try await settle(store)
        XCTAssertEqual(
            try XCTUnwrap(store.snapshot).document.node(id: a).position.x, 1 / store.canvasHeight, accuracy: 1e-12)
        let graph = try XCTUnwrap(store.snapshot).nodes.map(\.value)
        store.setMovingOrigin(true)
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if nodes(host).contains(where: { $0.isRectangular && $0.enabled && $0.precisionKey != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(window.firstResponder === node)
        XCTAssertFalse(node.enabled, "Origin mode suspends graph pointer input")
        node.keyDown(with: try key(125, window: window))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin?.y ?? 0, 0.5 + 1 / store.canvasHeight, accuracy: 1e-12)
        XCTAssertEqual(store.snapshot?.nodes.map(\.value), graph)
        let origin = try XCTUnwrap(nodes(host).first { $0.isRectangular && $0.enabled && $0.precisionKey != nil })
        try click(origin, window: window)
        XCTAssertTrue(window.firstResponder === origin)
        origin.keyDown(with: try key(125, window: window))
        try await settle(store)
        XCTAssertTrue(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.origin?.y ?? 0, 0.5 + 2 / store.canvasHeight, accuracy: 1e-12)
        XCTAssertEqual(store.snapshot?.nodes.map(\.value), graph)

        func canvases(_ view: NSView) -> [CanvasPointerView] {
            (view as? CanvasPointerView).map { [$0] } ?? view.subviews.flatMap(canvases)
        }
        store.setMovingOrigin(false)
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if canvases(host).first?.enabled == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let canvas = try XCTUnwrap(canvases(host).first)
        XCTAssertTrue(window.makeFirstResponder(canvas))
        store.setMovingOrigin(true)
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if !canvas.enabled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(canvas.enabled)
        XCTAssertTrue(window.firstResponder === canvas)
        canvas.keyDown(with: try key(123, window: window))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin?.x ?? 0, 0.5 - 1 / store.canvasHeight, accuracy: 1e-12)
        XCTAssertTrue(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.nodes.map(\.value), graph)
    }
    func testNativeTextTableAndMeshReceiversKeepTheirArrowKeys() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = root
        defer { window.contentView = nil }
        let canvas = CanvasPointerView(frame: root.bounds)
        canvas.enabled = true
        var edits = 0
        canvas.precisionKey = { _ in
            edits += 1
            return true
        }
        root.addSubview(canvas)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
        text.string = "abc"
        root.addSubview(text)
        XCTAssertTrue(window.makeFirstResponder(text))
        text.setSelectedRange(NSRange(location: 0, length: 0))
        window.firstResponder?.keyDown(with: try key(124, window: window))
        XCTAssertEqual(text.selectedRange().location, 1)
        let data = PrecisionTableData()
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 100, height: 150))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        table.dataSource = data
        root.addSubview(table)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(window.makeFirstResponder(table))
        window.firstResponder?.keyDown(with: try key(125, window: window))
        XCTAssertEqual(table.selectedRow, 1)
        let mesh = PrecisionMeshResponder(frame: root.bounds, device: nil)
        root.addSubview(mesh)
        XCTAssertTrue(window.makeFirstResponder(mesh))
        window.firstResponder?.keyDown(with: try key(124, window: window))
        XCTAssertEqual(mesh.received, 1)
        XCTAssertEqual(edits, 0)
    }
    func testSuccessfulPrecisionGestureNeverRestoresOldFieldAndExternalFocusWinsCancellation() async throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = root
        defer { window.contentView = nil }
        let field = PrecisionFocusResponder(frame: .zero)
        let other = PrecisionFocusResponder(frame: .zero)
        let node = NodePointerView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        for view in [field, other, node] { root.addSubview(view) }
        node.enabled = true
        node.canDrag = true
        node.precisionKey = { _ in true }
        var finishes = 0
        var cancellations = 0
        node.finish = { _, _ in finishes += 1 }
        node.cancel = { _ in cancellations += 1 }
        func event(_ type: NSEvent.EventType, x: Double) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: x, y: 18), modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1,
                    pressure: 1))
        }
        XCTAssertTrue(window.makeFirstResponder(field))
        node.mouseDown(with: try event(.leftMouseDown, x: 18))
        XCTAssertTrue(window.firstResponder === node)
        node.mouseDragged(with: try event(.leftMouseDragged, x: 28))
        node.mouseUp(with: try event(.leftMouseUp, x: 28))
        XCTAssertTrue(window.firstResponder === node)
        XCTAssertEqual(field.becomes, 1, "Success must not briefly restore the old field")
        XCTAssertEqual(finishes, 1)
        node.mouseDown(with: try event(.leftMouseDown, x: 18))
        node.mouseDragged(with: try event(.leftMouseDragged, x: 28))
        XCTAssertTrue(window.makeFirstResponder(other))
        XCTAssertTrue(window.makeFirstResponder(node))  // Returning does not revive the old gesture.
        await node.pendingCancellation?.value
        node.mouseUp(with: try event(.leftMouseUp, x: 28))
        XCTAssertTrue(window.firstResponder === node)
        XCTAssertEqual(finishes, 1)
        XCTAssertGreaterThan(cancellations, 0)
        XCTAssertEqual(field.becomes, 1)
    }
    func testDismantleCancelsNativeActivationNowAndDefersOnlyItsOwnedTokenCallback() async throws {
        let view = NodePointerView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        view.enabled = true
        view.canDrag = true
        var tokens: [UUID] = []
        var cancelled: [UUID] = []
        var finished: [UUID] = []
        view.begin = { tokens.append($0) }
        view.cancel = { cancelled.append($0) }
        view.finish = { token, _ in finished.append(token) }
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 18, y: 18), modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let drag = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged, location: NSPoint(x: 28, y: 18), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: NSPoint(x: 28, y: 18), modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        view.mouseDragged(with: drag)
        NodePointerSurface.dismantleNSView(view, coordinator: ())
        let delivery = view.pendingCancellation
        XCTAssertTrue(cancelled.isEmpty)
        view.mouseUp(with: up)
        XCTAssertTrue(finished.isEmpty)
        view.cancel = { _ in XCTFail("Old cancellation must not invoke a newer owner's callback") }
        view.enabled = true
        view.mouseDown(with: down)
        view.mouseDragged(with: drag)
        await delivery?.value
        XCTAssertEqual(cancelled, [try XCTUnwrap(tokens.first)])
        view.mouseUp(with: up)
        XCTAssertEqual(finished, [try XCTUnwrap(tokens.last)])
    }
    private func key(_ code: UInt16, window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let characters: String
        switch code {
        case 123: characters = "\u{F702}"
        case 124: characters = "\u{F703}"
        case 125: characters = "\u{F701}"
        case 126: characters = "\u{F700}"
        default: characters = ""
        }
        return try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
    private func click(_ view: NodePointerView, window: NSWindow) throws {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1,
                    pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Precision input did not settle")
    }
}
@MainActor private final class PrecisionOtherResponder: NSView { override var acceptsFirstResponder: Bool { true } }

@MainActor private final class PrecisionTableData: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 3 }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        "Row \(row)"
    }
}
@MainActor private final class PrecisionMeshResponder: InteractiveMeshView {
    var received = 0
    override func keyDown(with event: NSEvent) {
        received += 1
        super.keyDown(with: event)
    }
}

@MainActor private final class PrecisionFocusResponder: NSView {
    var becomes = 0
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        becomes += 1
        return true
    }
}
