import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class NodePointerViewTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, flags: NSEvent.ModifierFlags = []) throws
        -> NSEvent
    {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: .init(x: x, y: y), modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    func testClickCommandClickAndReadonlySelection() throws {
        let view = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        view.enabled = true
        var selected = 0
        var toggled = 0
        view.select = { selected += 1 }
        view.toggle = { toggled += 1 }
        view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 10))
        view.mouseUp(with: try event(.leftMouseUp, x: 10, y: 10))
        view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 10, flags: .command))
        view.mouseUp(with: try event(.leftMouseUp, x: 10, y: 10, flags: .command))
        XCTAssertEqual(selected, 1)
        XCTAssertEqual(toggled, 1)
    }

    func testEachDragCarriesItsOwnTokenAndWindowCoordinates() throws {
        let view = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        view.enabled = true
        view.canDrag = true
        var begins: [UUID] = []
        var updates: [(UUID, CanvasPoint)] = []
        var finishes: [(UUID, CanvasPoint)] = []
        view.begin = { begins.append($0) }
        view.update = { updates.append(($0, $1)) }
        view.finish = { finishes.append(($0, $1)) }
        for _ in 0..<2 {
            view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 20))
            view.mouseDragged(with: try event(.leftMouseDragged, x: 20, y: 25))
            view.mouseUp(with: try event(.leftMouseUp, x: 22, y: 26))
        }
        XCTAssertEqual(begins.count, 2)
        XCTAssertNotEqual(begins[0], begins[1])
        XCTAssertEqual(updates.map(\.0), begins)
        XCTAssertEqual(finishes.map(\.0), begins)
        XCTAssertEqual(updates[0].1, .init(x: 10, y: -5))
        XCTAssertEqual(finishes[0].1, .init(x: 12, y: -6))
    }

    func testRemovalCancelsOwnedActivation() throws {
        let view = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        view.enabled = true
        view.canDrag = true
        var begun: UUID?
        var cancelled: UUID?
        var finished = false
        view.begin = { begun = $0 }
        view.cancel = { cancelled = $0 }
        view.finish = { _, _ in finished = true }
        view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 10))
        view.viewWillMove(toWindow: nil)
        view.mouseUp(with: try event(.leftMouseUp, x: 20, y: 10))
        XCTAssertNotNil(begun)
        XCTAssertEqual(cancelled, begun)
        XCTAssertFalse(finished)
    }

    func testHitTestingUsesCircularTargetAndRespectsEnabledState() {
        let parent = NSView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        let view = NodePointerView(frame: .init(x: 20, y: 30, width: 36, height: 36))
        parent.addSubview(view)
        view.enabled = true
        XCTAssertTrue(view.hitTest(.init(x: 38, y: 48)) === view)
        XCTAssertNil(view.hitTest(.init(x: 20, y: 30)))
        view.enabled = false
        XCTAssertNil(view.hitTest(.init(x: 38, y: 48)))
    }

    func testRectangularTargetIncludes44PointCornersAndClickHasDistinctCancellation() throws {
        let parent = NSView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        let view = NodePointerView(frame: .init(x: 20, y: 30, width: 44, height: 44))
        parent.addSubview(view)
        view.enabled = true
        view.canDrag = true
        view.isRectangular = true
        XCTAssertTrue(view.hitTest(.init(x: 20, y: 30)) === view)
        XCTAssertTrue(view.hitTest(.init(x: 63, y: 73)) === view)
        var clicks = 0
        var interruptions = 0
        view.clickCancel = { _ in clicks += 1 }
        view.cancel = { _ in interruptions += 1 }
        view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 10))
        view.mouseUp(with: try event(.leftMouseUp, x: 10, y: 10))
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(interruptions, 0)
    }

    func testEscapeDuringDragCancelsOnceWithoutFinishing() throws {
        let view = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        view.enabled = true
        view.canDrag = true
        var begun: UUID?
        var cancellations: [UUID] = []
        var finishes = 0
        view.begin = { begun = $0 }
        view.cancel = { cancellations.append($0) }
        view.finish = { _, _ in finishes += 1 }
        view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 10))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 20, y: 10))
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        view.mouseUp(with: try event(.leftMouseUp, x: 20, y: 10))
        XCTAssertEqual(cancellations, [try XCTUnwrap(begun)])
        XCTAssertEqual(finishes, 0)
    }

    func testDragRestoresPriorResponderAndWindowResignCancels() throws {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        let prior = ResponderView(frame: .init(x: 50, y: 50, width: 20, height: 20))
        let view = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        window.contentView?.addSubview(prior)
        window.contentView?.addSubview(view)
        XCTAssertTrue(window.makeFirstResponder(prior))
        view.enabled = true
        view.canDrag = true
        var cancellations = 0
        var finishes = 0
        view.cancel = { _ in cancellations += 1 }
        view.finish = { _, _ in finishes += 1 }
        view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 10))
        XCTAssertTrue(window.firstResponder === prior)
        view.mouseDragged(with: try event(.leftMouseDragged, x: 20, y: 10))
        XCTAssertTrue(window.firstResponder === view)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        view.mouseUp(with: try event(.leftMouseUp, x: 20, y: 10))
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(finishes, 0)
        XCTAssertTrue(window.firstResponder === prior)
    }

    func testResponderDenialCancelsRatherThanCommittingDrag() throws {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let prior = RefusingResponderView(frame: .init(x: 50, y: 50, width: 20, height: 20))
        let view = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        window.contentView?.addSubview(prior)
        window.contentView?.addSubview(view)
        XCTAssertTrue(window.makeFirstResponder(prior))
        view.enabled = true
        view.canDrag = true
        var cancellations = 0
        var updates = 0
        var finishes = 0
        view.cancel = { _ in cancellations += 1 }
        view.update = { _, _ in updates += 1 }
        view.finish = { _, _ in finishes += 1 }
        view.mouseDown(with: try event(.leftMouseDown, x: 10, y: 10))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 20, y: 10))
        view.mouseUp(with: try event(.leftMouseUp, x: 20, y: 10))
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(finishes, 0)
        XCTAssertTrue(window.firstResponder === prior)
    }

    func testHostedCanvasHitTargetInvokesNodeDrag() async throws {
        let model = Data(
            "<canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='p'/></parts></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let original =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original)
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isWorking)
        let snapshot = try XCTUnwrap(store.snapshot)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        let node = try XCTUnwrap(snapshot.nodes.first)
        let point = projection.point(for: node.value.position)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 472, height: 472),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: NodeCanvas(store: store))
        host.frame = .init(x: 0, y: 0, width: 472, height: 472)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let start = NSPoint(x: point.x, y: 472 - point.y)
        let hit = try XCTUnwrap(host.hitTest(start) as? NodePointerView)
        hit.mouseDown(with: try event(.leftMouseDown, x: start.x, y: start.y))
        hit.mouseDragged(with: try event(.leftMouseDragged, x: start.x + 40, y: start.y))
        hit.mouseUp(with: try event(.leftMouseUp, x: start.x + 40, y: start.y))
        for _ in 0..<300 {
            if !store.isWorking { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let moved = try XCTUnwrap(store.snapshot?.nodes.first)
        XCTAssertGreaterThan(moved.value.position.x, node.value.position.x)
        XCTAssertTrue(store.canUndo)
    }

    func testHostedOriginPointerInvokesDragAndEscapeWithoutTouchingArchive() async throws {
        let original = Dust3DDocument.emptyArchive()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original)
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingReferenceImage { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let origin = try XCTUnwrap(store.snapshot?.origin)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        store.setMovingOrigin(true)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 472, height: 472),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: OriginHandle(store: store, origin: origin, projection: projection))
        host.frame = .init(x: 0, y: 0, width: 472, height: 472)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let point = projection.point(for: origin)
        let start = NSPoint(x: point.x, y: 472 - point.y)
        let hit = try XCTUnwrap(host.hitTest(start) as? NodePointerView)
        hit.mouseDown(with: try event(.leftMouseDown, x: start.x, y: start.y))
        hit.mouseDragged(with: try event(.leftMouseDragged, x: start.x + 40, y: start.y))
        XCTAssertNotNil(store.originDragPosition)
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53))
        hit.keyDown(with: escape)
        hit.mouseUp(with: try event(.leftMouseUp, x: start.x + 40, y: start.y))
        XCTAssertFalse(store.isMovingOrigin)
        XCTAssertNil(store.originDragPosition)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }
}

private final class ResponderView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private final class RefusingResponderView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { false }
}
