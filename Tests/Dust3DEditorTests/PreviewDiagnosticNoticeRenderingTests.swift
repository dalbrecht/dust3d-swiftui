import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class PreviewDiagnosticNoticeRenderingTests: XCTestCase {
    @MainActor
    func testOptionalDiagnosticsRenderAtPreviewWidthInBothAppearances() throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("preview-diagnostic-notice", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for kind in PreviewDiagnosticKind.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for isLong in [false, true] {
                    let cause =
                        isLong
                        ? "The \(kind.rawValue) payload exceeds its configured budget. Ordinary mesh generation remains available, and this original cause is preserved while editing and saving continue."
                        : "Not enough memory for preview \(kind.rawValue) data."
                    let data = try InspectorRenderer.png(
                        PreviewDiagnosticNotice(kind: kind, message: cause), width: 320, scheme: scheme)
                    let image = try XCTUnwrap(NSBitmapImageRep(data: data))
                    XCTAssertGreaterThanOrEqual(image.pixelsWide, 320)
                    let logicalHeight = Double(image.pixelsHigh) * 320 / Double(image.pixelsWide)
                    XCTAssertGreaterThan(logicalHeight, 40)
                    XCTAssertLessThan(logicalHeight, 350)
                    let name = "\(kind.rawValue)-\(scheme == .dark ? "dark" : "light")-\(isLong ? "long" : "short").png"
                    let url = directory.appendingPathComponent(name)
                    try data.write(to: url, options: .atomic)
                    print("Preview diagnostic QA artifact: \(url.path)")
                }
            }
        }
    }
}
