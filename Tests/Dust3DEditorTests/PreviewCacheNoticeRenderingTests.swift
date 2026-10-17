import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class PreviewCacheNoticeRenderingTests: XCTestCase {
    @MainActor
    func testCacheDiagnosticRendersAtPreviewWidthInBothAppearances() throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("preview-cache-notice", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for isLong in [false, true] {
                let cause =
                    isLong
                    ? "Generated cache payload exceeds the session cache budget. The preview remains valid, and the original diagnostic stays available for inspection."
                    : "Not enough memory to retain the preview cache."
                let data = try InspectorRenderer.png(PreviewCacheNotice(message: cause), width: 320, scheme: scheme)
                let image = try XCTUnwrap(NSBitmapImageRep(data: data))
                XCTAssertGreaterThanOrEqual(image.pixelsWide, 320)
                let logicalHeight = Double(image.pixelsHigh) * 320 / Double(image.pixelsWide)
                XCTAssertGreaterThan(logicalHeight, 40)
                XCTAssertLessThan(logicalHeight, 350)
                let name = "cache-\(scheme == .dark ? "dark" : "light")-\(isLong ? "long" : "short").png"
                let url = directory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                print("Preview cache QA artifact: \(url.path)")
            }
        }
    }
}
