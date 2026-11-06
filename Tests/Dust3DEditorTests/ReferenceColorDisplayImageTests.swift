import AppKit
import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class ReferenceColorDisplayImageTests: XCTestCase {
    private func document(_ png: Data) throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(.setReferenceImagePNG(png))
    }

    private func providerBytes(_ image: CGImage) throws -> Data { try XCTUnwrap(image.dataProvider?.data) as Data }

    private func customGrayPNG() throws -> Data { try ReferenceColorPNGFixtures.customGrayPNG() }

    func testRgbDisplayUsesExactlyFittedStraightPixelsIncludingHiddenRgb() throws {
        let png = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(ReferenceColorPNGFixtures.orientations[1])))
        let result = try ReferenceColorRasterCodec.prepare(
            document: document(png), fittedSize: .init(width: 2, height: 3))
        XCTAssertEqual(result.displayImage.width, result.raster.size.width)
        XCTAssertEqual(result.displayImage.height, result.raster.size.height)
        XCTAssertEqual(result.displayImage.bitsPerPixel, 32)
        XCTAssertEqual(result.displayImage.colorSpace?.numberOfComponents, 3)
        XCTAssertEqual(Array(try providerBytes(result.displayImage).prefix(8)), [11, 21, 31, 0, 12, 22, 32, 1])
        XCTAssertEqual(result.raster.color(x: 0, y: 0), .init(red: 11, green: 21, blue: 31, alpha: 0))
    }

    func testCustomGrayProfileUsesGrayAlphaPackingRatherThanAttachingGrayProfileToRgba() throws {
        let png = try customGrayPNG()
        let result = try ReferenceColorRasterCodec.prepare(
            document: document(png), fittedSize: .init(width: 2, height: 2))
        XCTAssertEqual(result.sourceColorSpace?.model, .monochrome)
        XCTAssertEqual(result.displayImage.colorSpace?.model, .monochrome)
        XCTAssertEqual(result.displayImage.bitsPerComponent, 8)
        XCTAssertEqual(result.displayImage.bitsPerPixel, 16)
        XCTAssertEqual(result.displayImage.alphaInfo, .last)
        XCTAssertEqual(try providerBytes(result.displayImage), Data([17, 255, 100, 255, 200, 255, 250, 255]))
        let sourceICC = try XCTUnwrap(result.sourceColorSpace?.copyICCData()) as Data
        let displayICC = try XCTUnwrap(result.displayImage.colorSpace?.copyICCData()) as Data
        XCTAssertEqual(sourceICC, displayICC)
        XCTAssertEqual(result.referencePNG, png)
        XCTAssertEqual(result.raster.color(x: 0, y: 0), .init(red: 17, green: 17, blue: 17))
    }

    func testGrayAlphaPackingPreservesHiddenGrayAndLowAlphaWithoutCompositing() throws {
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGMQZDjxHwAC2AHZjeSxLgAAAABJRU5ErkJggg=="))
        let result = try ReferenceColorRasterCodec.prepare(
            document: document(png), fittedSize: .init(width: 2, height: 1))
        XCTAssertEqual(result.displayImage.bitsPerPixel, 16)
        XCTAssertEqual(try providerBytes(result.displayImage), Data([17, 0, 200, 255]))
        XCTAssertEqual(result.raster.color(x: 0, y: 0), .init(red: 17, green: 17, blue: 17, alpha: 0))
    }

    func testInconsistentGrayChannelsOrUnsupportedProfileRejectRatherThanLosingColor() throws {
        let raster = try ReferenceColorRaster(width: 1, height: 1, rowStride: 4, pixels: Data([10, 20, 30, 0]))
        XCTAssertThrowsError(
            try ReferenceColorDisplayImage.make(raster: raster, colorSpace: CGColorSpaceCreateDeviceGray())
        ) {
            XCTAssertEqual($0 as? ReferenceColorRasterError, .incompatibleGrayPixels)
        }
        XCTAssertThrowsError(try ReferenceColorDisplayImage.make(raster: raster, colorSpace: nil)) {
            XCTAssertEqual($0 as? ReferenceColorRasterError, .unsupportedDisplayProfile)
        }
    }

    func testPaddedRgbRowsBecomeTightDisplayPixelsWithoutLeakingPadding() throws {
        let bytes = Data([1, 2, 3, 4, 90, 90, 90, 90, 5, 6, 7, 8])
        let raster = try ReferenceColorRaster(width: 1, height: 2, rowStride: 8, pixels: bytes)
        let image = try ReferenceColorDisplayImage.make(raster: raster, colorSpace: CGColorSpaceCreateDeviceRGB())
        XCTAssertEqual(image.bytesPerRow, 4)
        XCTAssertEqual(try providerBytes(image), Data([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    @MainActor func testActualSwiftUiGrayProfileRenderingMatchesOriginalAtSolidInteriors() throws {
        let png = try customGrayPNG()
        let original = try ReferenceImageCodec.decodePNG(png)
        let result = try ReferenceColorRasterCodec.prepare(
            document: document(png), fittedSize: .init(width: 8, height: 8))
        var bitmaps: [NSBitmapImageRep] = []
        for image in [original, result.displayImage] {
            let rendered = try InspectorRenderer.png(
                Image(decorative: image, scale: 1).interpolation(.none).resizable()
                    .frame(width: 128, height: 128).opacity(0.5),
                width: 160, scheme: .light)
            bitmaps.append(try XCTUnwrap(NSBitmapImageRep(data: rendered)))
        }
        XCTAssertEqual(bitmaps[0].pixelsWide, bitmaps[1].pixelsWide)
        XCTAssertEqual(bitmaps[0].pixelsHigh, bitmaps[1].pixelsHigh)
        for fractionX in [0.25, 0.75] {
            for fractionY in [0.25, 0.75] {
                let x = Int(Double(bitmaps[0].pixelsWide) * fractionX)
                let y = Int(Double(bitmaps[0].pixelsHigh) * fractionY)
                let first = try XCTUnwrap(bitmaps[0].colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let second = try XCTUnwrap(bitmaps[1].colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                XCTAssertEqual(first.redComponent, second.redComponent, accuracy: 1.0 / 255)
                XCTAssertEqual(first.greenComponent, second.greenComponent, accuracy: 1.0 / 255)
                XCTAssertEqual(first.blueComponent, second.blueComponent, accuracy: 1.0 / 255)
            }
        }
    }
}
