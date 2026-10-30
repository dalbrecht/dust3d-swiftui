import AppKit
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class GeometryExportRenderingTests: XCTestCase {
    func testAccessibilityReplacesSelectableExportWarning() async throws {
        _ = NSApplication.shared
        let receipt = EditorExportReceipt(
            documentIdentity: UUID(), documentRevision: 7,
            destination: URL(fileURLWithPath: "/owned/Capsule.obj"),
            format: .obj, byteCount: 5143, warning: "Geometry only")
        let secondReceipt = EditorExportReceipt(
            documentIdentity: UUID(), documentRevision: 8,
            destination: URL(fileURLWithPath: "/owned/Capsule.fbx"),
            format: .fbx, byteCount: 5144, warning: "Textures omitted")
        let host = NSHostingView(
            rootView: EditorGeometryExportStatusView(
                phase: .completed(receipt), onCancel: {}, onDismiss: {}))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }

        func strings() -> [String] {
            host.layoutSubtreeIfNeeded()
            var visited = Set<ObjectIdentifier>()
            return accessibilityStrings(window, visited: &visited)
        }
        for _ in 0..<100 where !strings().contains(where: { $0.contains("Geometry only") }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(strings().contains(where: { $0.contains("Geometry only") }))
        host.rootView = EditorGeometryExportStatusView(phase: .completed(secondReceipt), onCancel: {}, onDismiss: {})
        for _ in 0..<100 where !strings().contains(where: { $0.contains("Textures omitted") }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let completed = strings()
        XCTAssertTrue(completed.contains(where: { $0.contains("Textures omitted") }), "\(completed)")
        XCTAssertFalse(completed.contains(where: { $0.contains("Geometry only") }), "\(completed)")
    }

    private func accessibilityStrings(_ object: Any, visited: inout Set<ObjectIdentifier>) -> [String] {
        guard let element = object as? any NSAccessibilityProtocol,
            visited.count < 512, visited.insert(ObjectIdentifier(element)).inserted
        else { return [] }
        let own = [element.accessibilityLabel(), element.accessibilityValue() as? String].compactMap { $0 }
        let children = (element.accessibilityChildren() ?? []) + ((object as? NSView)?.subviews ?? [])
        return own + children.flatMap { accessibilityStrings($0, visited: &visited) }
    }

    func testActualFormatMenuAndStatusesRenderOffscreenWithoutPublishing() throws {
        var publications = 0
        let receipt = EditorExportReceipt(
            documentIdentity: UUID(), documentRevision: 7,
            destination: URL(fileURLWithPath: "/owned/Original-procedural-capsule-with-a-long-file-name.fbx"),
            format: .fbx, byteCount: 12345,
            warning: "Materials and textures are excluded from geometry export.")
        let states: [(String, EditorGeometryExportPhase)] = [
            ("ready", .idle), ("choosing", .choosing), ("encoding", .encoding),
            ("cancelling", .cancelling), ("completed", .completed(receipt)),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, phase) in states {
                let view = VStack(alignment: .leading) {
                    EditorGeometryExportMenu(
                        canExport: (name == "ready" || name == "completed"), onExport: { _ in publications += 1 })
                    EditorGeometryExportStatusView(
                        phase: phase, format: .fbx, onCancel: {}, onDismiss: {})
                }
                let png = try InspectorRenderer.png(view, width: 640, scheme: scheme)
                XCTAssertGreaterThan(png.count, 100)
                if let directory = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                    let url = URL(fileURLWithPath: directory, isDirectory: true)
                        .appendingPathComponent(
                            "geometry-export-" + name + "-" + (scheme == .dark ? "dark" : "light") + ".png")
                    try png.write(to: url, options: .atomic)
                }
            }
        }
        XCTAssertEqual(publications, 0)
    }
}
