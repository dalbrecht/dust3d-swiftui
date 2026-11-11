import AppKit
import XCTest

@testable import Dust3DEditor

@MainActor final class CanvasPreviewDragTests: XCTestCase {
    func testCameraPressesPreserveGraphAndContextModifiers() {
        XCTAssertTrue(CanvasPreviewDrag.accepts(button: 2, modifiers: []))
        XCTAssertTrue(CanvasPreviewDrag.accepts(button: 2, modifiers: .shift))
        XCTAssertTrue(CanvasPreviewDrag.accepts(button: 0, modifiers: .option))
        XCTAssertTrue(CanvasPreviewDrag.accepts(button: 0, modifiers: [.option, .shift]))
        XCTAssertFalse(CanvasPreviewDrag.accepts(button: 0, modifiers: [.command, .option]))
        XCTAssertFalse(CanvasPreviewDrag.accepts(button: 0, modifiers: [.control, .option]))
        XCTAssertFalse(CanvasPreviewDrag.accepts(button: 0, modifiers: .shift))
        XCTAssertFalse(CanvasPreviewDrag.accepts(button: 1, modifiers: []))
        XCTAssertFalse(CanvasPreviewDrag.accepts(button: 3, modifiers: []))
    }

    func testCapturedDragDeliversIncrementalMotionAndRetiresRejectedUpdates() {
        var gesture = CanvasPreviewDrag()
        var received: [(SIMD2<Float>, Bool)] = []
        var releases = 0
        var admitsUpdate = true
        let begin: CanvasPreviewDrag.Begin = {
            .init(
                update: { delta, pans in
                    guard admitsUpdate else { return false }
                    received.append((delta, pans))
                    return true
                },
                end: { releases += 1 })
        }
        XCTAssertFalse(gesture.press(button: 0, modifiers: .command, location: .zero, begin: begin))
        XCTAssertTrue(gesture.press(button: 2, modifiers: [], location: .init(x: 10, y: 20), begin: begin))
        XCTAssertFalse(gesture.drag(button: 0, modifiers: [], location: .init(x: 12, y: 21)))
        XCTAssertTrue(gesture.drag(button: 2, modifiers: [], location: .init(x: 12, y: 21)))
        XCTAssertTrue(gesture.drag(button: 2, modifiers: .shift, location: .init(x: 10, y: 26)))
        XCTAssertEqual(received.map { $0.0 }, [SIMD2(2, 1), SIMD2(-2, 5)])
        XCTAssertEqual(received.map { $0.1 }, [false, true])

        admitsUpdate = false
        XCTAssertTrue(gesture.drag(button: 2, modifiers: [], location: .init(x: 10, y: 30)))
        XCTAssertEqual(releases, 1)
        admitsUpdate = true
        XCTAssertTrue(gesture.drag(button: 2, modifiers: [], location: .init(x: 10, y: 35)))
        XCTAssertTrue(gesture.release(button: 2))
        XCTAssertFalse(gesture.release(button: 2))
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(releases, 1)
    }

    func testOptionDragIsHandledByBothCanvasAndNodeBeforeGraphInput() throws {
        let canvas = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let node = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        canvas.enabled = true
        node.enabled = true
        node.canDrag = true
        canvas.tap = { _, _ in XCTFail("Camera drag must not pick") }
        canvas.select = { _, _ in XCTFail("Camera drag must not select a region") }
        node.begin = { _ in XCTFail("Camera drag must not move a node") }
        node.select = { XCTFail("Camera drag must not select a node") }
        var motions: [SIMD2<Float>] = []
        var releases = 0
        let window = CanvasPreviewKeyWindow(
            contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        func event(_ type: NSEvent.EventType, x: Double, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: .init(x: x, y: 10), modifierFlags: modifiers, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        for view: CanvasCameraPointerView in [canvas, node] {
            window.contentView = view
            view.beginPreviewDrag = {
                .init(
                    update: { delta, pans in
                        XCTAssertTrue(pans)
                        motions.append(delta)
                        return true
                    }, end: { releases += 1 })
            }
            view.mouseDown(with: try event(.leftMouseDown, x: 10, modifiers: .option))
            XCTAssertTrue(window.firstResponder === view)
            view.mouseDragged(with: try event(.leftMouseDragged, x: 22, modifiers: .shift))
            view.mouseUp(with: try event(.leftMouseUp, x: 22, modifiers: []))
        }
        XCTAssertEqual(motions, [SIMD2(12, 0), SIMD2(12, 0)])
        XCTAssertEqual(releases, 2)

        let container = NSView(frame: canvas.frame)
        let previous = CanvasPreviewPreviousResponder()
        window.contentView = container
        container.addSubview(canvas)
        container.addSubview(previous)
        XCTAssertTrue(window.makeFirstResponder(previous))
        canvas.beginPreviewDrag = { nil }
        XCTAssertFalse(canvas.routePreviewPress(try event(.leftMouseDown, x: 10, modifiers: .option)))
        XCTAssertTrue(window.firstResponder === previous)
    }

    func testUnavailableCameraAndCancellationDoNotStartOrReuseASequence() {
        var gesture = CanvasPreviewDrag()
        XCTAssertFalse(gesture.press(button: 0, modifiers: .option, location: .zero, begin: { nil }))
        XCTAssertFalse(gesture.release(button: 0))
        var releases = 0
        XCTAssertTrue(
            gesture.press(button: 0, modifiers: .option, location: .zero) {
                .init(update: { _, _ in true }, end: { releases += 1 })
            })
        gesture.cancel()
        gesture.cancel()
        XCTAssertEqual(releases, 1)
        XCTAssertFalse(gesture.release(button: 0))
    }
}

private final class CanvasPreviewKeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

private final class CanvasPreviewPreviousResponder: NSView {
    override var acceptsFirstResponder: Bool { true }
}
