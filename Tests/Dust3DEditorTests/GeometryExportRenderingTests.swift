import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class GeometryExportRenderingTests: XCTestCase {
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
