import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor final class EndpointBendInputTests: XCTestCase {
    func testNativeReturnRejectsInvalidCoordinatesAndCommitsOneBend() async throws {
        let xml = """
            <canvas><nodes>
            <node id='root' partId='p' x='0' y='0' z='0' radius='.2'/>
            <node id='tip' partId='p' x='1' y='0' z='0' radius='.1'/>
            </nodes><edges><edge id='e' partId='p' from='root' to='tip'/></edges>
            <parts><part id='p'/></parts></canvas>
            """
        let source = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.select("tip")
        try await settle(store)
        let snapshot = try XCTUnwrap(store.snapshot)
        let target = try XCTUnwrap(EndpointIKTarget(endpointID: "tip", snapshot: snapshot))
        let context = try XCTUnwrap(store.canvasRotationContext)
        let host = NSHostingView(
            rootView: EndpointBendFields(store: store, context: context, target: target, locks: snapshot.locks))
        let window = NSWindow(
            contentRect: .init(x: -10000, y: -10000, width: 420, height: 250),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        let inputs = fields(host).filter(\.isEditable)
        XCTAssertEqual(inputs.count, 2)
        let vertical = try XCTUnwrap(inputs.last)
        let enter = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        for text in ["invalid", "1"] {
            XCTAssertTrue(window.makeFirstResponder(vertical))
            let editor = try XCTUnwrap(window.fieldEditor(true, for: vertical) as? NSTextView)
            editor.string = text
            editor.didChangeText()
            editor.keyDown(with: enter)
            await Task.yield()
            try await settle(store)
            if text == "invalid" {
                XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
        let changed = try XCTUnwrap(store.snapshot)
        let tip = try changed.document.node(id: "tip")
        XCTAssertEqual(tip.position.x, 1 / sqrt(2), accuracy: 1e-12)
        XCTAssertEqual(tip.position.y, 1 / sqrt(2), accuracy: 1e-12)
        XCTAssertEqual(tip.radius, 0.1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Endpoint input did not settle")
    }
}
