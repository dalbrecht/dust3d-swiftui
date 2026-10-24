import AppKit
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class ReferenceCropPreviewRenderingTests: XCTestCase {
    @MainActor func testDrawAndAdjustRenderDistinctLightDarkAndMirroredPreviewsWithoutPublishingACrop() throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 640,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        context.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 40, y: 20, width: 80, height: 60))
        let image = try XCTUnwrap(context.makeImage())
        let crop = try ReferenceImageCrop(size: .init(width: 160, height: 100), x: 20, y: 10, width: 100, height: 70)
        var published = false
        for mirrored in [false, true] {
            let source = try ReferenceCompositionSource(image: image, crop: crop, isMirrored: mirrored)
            for scheme in [ColorScheme.light, .dark] {
                var draw: Data?
                for adjusting in [false, true] {
                    let preview = ReferenceCropPreview(source: source, isAdjusting: adjusting) { _ in
                        published = true
                    } failure: { error in
                        XCTFail("Rendering rejected valid crop: \(error)")
                    } activity: { _, active in
                        XCTAssertFalse(active, "Rendering must not begin a pointer edit")
                    }
                    let png = try InspectorRenderer.png(preview, width: 400, scheme: scheme)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
                    XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                    XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                    if adjusting {
                        XCTAssertNotEqual(png, try XCTUnwrap(draw), "Adjust must visibly add resize handles")
                    } else {
                        draw = png
                    }
                    if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                        let directory = URL(fileURLWithPath: output, isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let name =
                            "crop-\(adjusting ? "adjust" : "draw")-\(mirrored ? "mirrored" : "front")-\(scheme == .dark ? "dark" : "light").png"
                        try png.write(to: directory.appendingPathComponent(name), options: .atomic)
                    }
                    XCTAssertEqual(source.crop, crop)
                    XCTAssertFalse(published)
                }
            }
        }
    }
}
