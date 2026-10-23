import AppKit
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class SelectableNodeIdentifierTests: XCTestCase {
    @MainActor
    func testIdentityUsesReadOnlyNativeSelectionAndOwnedClipboard() async throws {
        _ = NSApplication.shared
        let identifier = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let host = NSHostingView(rootView: SelectableNodeIdentifier(value: identifier))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0..<100 where label(in: host) == nil {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let field = try XCTUnwrap(label(in: host))
        XCTAssertTrue(field.isSelectable)
        XCTAssertFalse(field.isEditable)
        XCTAssertEqual(field.stringValue, identifier)
        window.makeKey()
        field.selectText(nil)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertFalse(editor.isEditable)
        XCTAssertEqual(editor.string, identifier)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: identifier.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let textType = try XCTUnwrap(editor.writablePasteboardTypes.first)
        pasteboard.declareTypes([textType], owner: nil)
        XCTAssertTrue(editor.writeSelection(to: pasteboard, types: [textType]))
        XCTAssertEqual(pasteboard.string(forType: textType), identifier)
        host.rootView = SelectableNodeIdentifier(value: "second-identifier")
        for _ in 0..<100 where field.stringValue != "second-identifier" {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(field.stringValue, "second-identifier")
        XCTAssertEqual(field.accessibilityValue(), "second-identifier")
        if let activeEditor = field.currentEditor() {
            XCTAssertEqual(activeEditor.string, "second-identifier")
        }
    }

    @MainActor
    private func label(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap { self.label(in: $0) }.first
    }
}
