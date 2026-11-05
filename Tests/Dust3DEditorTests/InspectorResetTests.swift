import AppKit
import Dust3DDocument
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class InspectorResetTests: XCTestCase {
    @MainActor
    func testResetRestoresEmptyAndInvalidNativeNumericText() async throws {
        _ = NSApplication.shared
        let store = EditorStore()
        let blank = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let document = try blank.applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0.5, y: 0.25, z: 1), radius: 0.12))
        await store.load(data: document.encoded())
        defer { store.stop() }
        store.select("a")
        for _ in 0..<100 where store.snapshot?.selectedID != "a" {
            try await Task.sleep(for: .milliseconds(10))
        }
        let selected = try XCTUnwrap(store.snapshot?.selectedNode)
        let node = selected.value
        let draft = InspectorNodeDraft()
        draft.reset(node)
        // Scope the real native formatter test to the production numeric editor. Other
        // inspector commands have independent text drafts and must not participate in Reset.
        let host = NSHostingView(rootView: NodePropertyEditor(store: store, node: selected, draft: draft))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 800), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0..<100 where fields(in: host).count != 4 {
            try await Task.sleep(for: .milliseconds(10))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(fields(in: host).count, 4)
        XCTAssertEqual(
            Set(fields(in: host).map(\.stringValue)),
            Set([node.position.x, node.position.y, node.position.z, node.radius].map { $0.formatted(.number) }))
        let expected = node.position.x.formatted(.number)
        for invalidText in ["", "oops"] {
            let matches = fields(in: host).filter { $0.stringValue == expected }
            XCTAssertEqual(matches.count, 1, "The fixture's X draft is unique; view traversal order is irrelevant")
            let field = try XCTUnwrap(matches.first)
            XCTAssertEqual(field.stringValue, expected)
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText(invalidText, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            XCTAssertEqual(editor.string, invalidText)
            XCTAssertEqual(draft.x, 0.5)
            // Invoke the same Reset action as the button while a real native field holds invalid text.
            draft.reset(node)
            for _ in 0..<100 where displayedText(in: host, matching: expected) != expected {
                try await Task.sleep(for: .milliseconds(10))
                host.layoutSubtreeIfNeeded()
            }
            XCTAssertEqual(displayedText(in: host, matching: expected), expected)
        }
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.snapshot?.canUndo ?? true)
        XCTAssertFalse(store.snapshot?.canRedo ?? true)
    }

    @MainActor
    private func displayedText(in view: NSView, matching expected: String) -> String? {
        guard let field = fields(in: view).first(where: { $0.stringValue == expected }) else { return nil }
        return field.currentEditor()?.string ?? field.stringValue
    }

    @MainActor
    private func fields(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? []
        return own + view.subviews.flatMap { fields(in: $0) }
    }
}
