import AppKit
import Dust3DDocument
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class InspectorIdentityTests: XCTestCase {
    @MainActor
    func testSelectableIdentityAccessibilityFollowsSelection() async throws {
        _ = NSApplication.shared
        let firstID = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let secondID = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
        let blank = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let first = try blank.applying(
            .addNode(
                id: firstID, partID: "first-part", componentID: "first-component",
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
        let document = try first.applying(
            .addNode(
                id: secondID, partID: "second-part", componentID: "second-component",
                position: .init(x: 0.5, y: 0.75, z: 0.5), radius: 0.1))
        let store = EditorStore()
        await store.load(data: document.encoded())
        defer { store.stop() }
        let host = NSHostingView(rootView: NodeInspector(store: store).environment(EditorPasteboard()))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        for identity in [firstID, secondID, firstID] {
            store.select(identity)
            for _ in 0..<100 where store.snapshot?.selectedID != identity {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(store.snapshot?.selectedID, identity)
            var values: [String] = []
            for _ in 0..<100 {
                host.layoutSubtreeIfNeeded()
                var visited = Set<ObjectIdentifier>()
                values = accessibilityValues(window, visited: &visited)
                if values.contains(where: { $0.contains(identity) }) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(
                values.contains(where: { $0.contains(identity) }),
                "Selected identity missing from accessibility values: \(values)")
            let obsolete = identity == firstID ? secondID : firstID
            XCTAssertFalse(values.contains(where: { $0.contains(obsolete) }), "Previous identity remains accessible")
        }
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.snapshot?.canUndo ?? true)
    }

    @MainActor
    private func accessibilityValues(_ object: Any, visited: inout Set<ObjectIdentifier>) -> [String] {
        guard let element = object as? any NSAccessibilityProtocol,
            visited.count < 512, visited.insert(ObjectIdentifier(element)).inserted
        else { return [] }
        let own = (element.accessibilityValue() as? String).map { [$0] } ?? []
        let children = (element.accessibilityChildren() ?? []) + ((object as? NSView)?.subviews ?? [])
        return own
            + children.flatMap {
                accessibilityValues($0, visited: &visited)
            }
    }
}
