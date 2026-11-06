import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Dust3DEditor

@MainActor
final class ReferenceColorRasterServiceTests: XCTestCase {
    private func png(_ orientation: Int = 1) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: XCTUnwrap(ReferenceColorPNGFixtures.orientations[orientation])))
    }

    private func document(_ png: Data) throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(.setReferenceImagePNG(png))
    }

    private func redRows(_ raster: ReferenceColorRaster) throws -> [UInt8] {
        try (0..<raster.size.height).flatMap { y in
            try (0..<raster.size.width).map { x in try XCTUnwrap(raster.color(x: x, y: y)).red }
        }
    }

    func testAllExifOrientationsMatchNativeReferenceDisplayWithoutPremultiplication() throws {
        let expected: [[UInt8]] = [
            [11, 12, 13, 14, 15, 16], [12, 11, 14, 13, 16, 15],
            [16, 15, 14, 13, 12, 11], [15, 16, 13, 14, 11, 12],
            [11, 13, 15, 12, 14, 16], [15, 13, 11, 16, 14, 12],
            [16, 14, 12, 15, 13, 11], [12, 14, 16, 11, 13, 15],
        ]
        for orientation in 1...8 {
            let bytes = try png(orientation)
            let source = try document(bytes)
            let size = try ReferencePixelSize(width: orientation < 5 ? 2 : 3, height: orientation < 5 ? 3 : 2)
            let result = try ReferenceColorRasterCodec.prepare(document: source, fittedSize: size)
            XCTAssertEqual(result.referenceSize, size)
            XCTAssertEqual(try redRows(result.raster), expected[orientation - 1])
            let displayed = try ReferenceImageCodec.decodePNG(bytes)
            XCTAssertEqual(displayed.width, size.width)
            XCTAssertEqual(displayed.height, size.height)
            XCTAssertEqual(result.referencePNG, bytes)
            XCTAssertEqual(source.referenceImagePNG, bytes)
            let hidden = try (0..<size.height).flatMap { y in
                try (0..<size.width).map { x in try XCTUnwrap(result.raster.color(x: x, y: y)) }
            }.first { $0.alpha == 0 }
            XCTAssertEqual(hidden, .init(red: 11, green: 21, blue: 31, alpha: 0))
        }
    }

    func testFittedGridIsExplicitAndMatchesCapturedQtAliasedBoundaries() throws {
        // Opaque 2x3 source separates spatial selection from alpha conversion.
        // Qt 6.12.0 IgnoreAspectRatio/FastTransformation: 1x1 -> red13;
        // 3x2 -> reds11,11,12 /15,15,16. No Qt is needed by this test.
        let opaque = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAI0lEQVR4nGPgFpX/zyOm8J+BV1zxP5+E0n8Gfknl/wJSKv8BXZMHoqcZPKIAAAAASUVORK5CYII="
            ))
        let source = try document(opaque)
        let one = try ReferenceColorRasterCodec.prepare(document: source, fittedSize: .init(width: 2, height: 3))
        let two = try ReferenceColorRasterCodec.prepare(document: source, fittedSize: .init(width: 4, height: 6))
        XCTAssertEqual(two.raster.size.width, one.raster.size.width * 2)
        XCTAssertEqual(two.raster.color(x: 0, y: 0), one.raster.color(x: 0, y: 0))
        XCTAssertEqual(two.raster.color(x: 1, y: 1), one.raster.color(x: 0, y: 0))
        let down = try ReferenceColorRasterCodec.prepare(document: source, fittedSize: .init(width: 1, height: 1))
        XCTAssertEqual(down.raster.color(x: 0, y: 0)?.red, 13)
        let mixed = try ReferenceColorRasterCodec.prepare(document: source, fittedSize: .init(width: 3, height: 2))
        XCTAssertEqual(try redRows(mixed.raster), [11, 11, 12, 15, 15, 16])
    }

    func testGrayPaletteAndQtDepthSpecificTransparencyPolicyReuseExistingDecoder() throws {
        let cases: [(String, DocumentColor)] = [
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGMQZDjxHwAC2AHZjeSxLgAAAABJRU5ErkJggg==",
                .init(red: 17, green: 17, blue: 17, alpha: 0)
            ),
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAAnRSTlMAERwj7coAAAALSURBVHicYxA8AQAA7QDaiakNYwAAAABJRU5ErkJggg==",
                .init(red: 0, green: 0, blue: 0, alpha: 0)
            ),
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC",
                .init(red: 255, green: 0, blue: 0, alpha: 128)
            ),
        ]
        for (base64, expected) in cases {
            let result = try ReferenceColorRasterCodec.prepare(
                document: document(XCTUnwrap(Data(base64Encoded: base64))), fittedSize: .init(width: 2, height: 1))
            XCTAssertEqual(result.raster.color(x: 0, y: 0), expected)
        }
    }

    func testProfileTaggedPaddedProviderPreservesSourceChannelsAndProfileMetadata() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let pixels = Data([
            100, 80, 60, 255, 200, 150, 100, 128, 99, 99, 99, 99, 50, 60, 70, 255, 80, 90, 100, 255, 98, 98, 98, 98,
        ])
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12, space: space,
                bitmapInfo: .init(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try ReferenceColorRasterCodec.prepare(
            document: document(output as Data), fittedSize: .init(width: 2, height: 2))
        XCTAssertEqual(result.raster.color(x: 0, y: 0), .init(red: 100, green: 80, blue: 60))
        XCTAssertEqual(result.raster.color(x: 1, y: 0), .init(red: 200, green: 150, blue: 100, alpha: 128))
        XCTAssertEqual(result.raster.color(x: 0, y: 1), .init(red: 50, green: 60, blue: 70))
        XCTAssertEqual(result.sourceColorSpace?.model, .rgb)
        XCTAssertEqual(result.sourceColorSpace?.name, CGColorSpace.displayP3)
    }

    func testLogicalPayloadLimitsAreCheckedBeforeFittedAllocationAndKeepDecoderCause() throws {
        let source = try document(png())
        let exact = try ReferenceColorRasterCodec.prepare(
            document: source, fittedSize: .init(width: 2, height: 3), maximumDecodedBytes: 24, maximumFittedBytes: 24)
        XCTAssertEqual(exact.raster.size.height, 3)
        XCTAssertThrowsError(
            try ReferenceColorRasterCodec.prepare(
                document: source, fittedSize: .init(width: 2, height: 3), maximumDecodedBytes: 23)
        ) {
            XCTAssertEqual($0 as? MeshPNGDecodingError, .decodedLimitExceeded)
        }
        XCTAssertThrowsError(
            try ReferenceColorRasterCodec.prepare(
                document: source, fittedSize: .init(width: 2, height: 3), maximumFittedBytes: 23)
        ) {
            XCTAssertEqual($0 as? ReferenceColorRasterError, .fittedLimitExceeded)
        }
        XCTAssertThrowsError(
            try ReferenceColorRasterCodec.prepare(
                document: source, fittedSize: .init(width: 1, height: 1), maximumFittedBytes: 0)
        ) {
            XCTAssertEqual($0 as? ReferenceColorRasterError, .invalidLimits)
        }
        let empty = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        XCTAssertThrowsError(
            try ReferenceColorRasterCodec.prepare(document: empty, fittedSize: .init(width: 1, height: 1))
        ) {
            XCTAssertEqual($0 as? ReferenceColorRasterError, .missingReference)
        }
        let invalid = try document(Data([137, 80, 78, 71, 13, 10, 26, 10]))
        XCTAssertThrowsError(
            try ReferenceColorRasterCodec.prepare(document: invalid, fittedSize: .init(width: 1, height: 1))
        ) {
            XCTAssertEqual($0 as? MeshPNGDecodingError, .invalidPNG)
        }
    }

    func testServiceUsesCapturedDocumentBytesAndCancellationNeverPublishesRaster() async throws {
        let source = try document(png())
        let service = ReferenceColorRasterService()
        let first = try await service.prepare(document: source, fittedSize: .init(width: 2, height: 3))
        let capturedDisplay = try XCTUnwrap(first.displayImage.dataProvider?.data) as Data
        let replacement = try source.applying(.setReferenceImagePNG(png(6)))
        _ = try await service.prepare(document: replacement, fittedSize: .init(width: 3, height: 2))
        XCTAssertEqual(first.raster.color(x: 0, y: 0), .init(red: 11, green: 21, blue: 31, alpha: 0))
        XCTAssertEqual(first.referencePNG, source.referenceImagePNG)
        XCTAssertEqual(try XCTUnwrap(first.displayImage.dataProvider?.data) as Data, capturedDisplay)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.prepare(document: source, fittedSize: .init(width: 2, height: 3))
        }
        do {
            _ = try await cancelled.value
            XCTFail("A pre-cancelled operation cannot publish fitted pixels")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testLogicalHeightFitsFreshOrientedMetadataWithoutAnyPreviewImageSize() async throws {
        let source = try document(png(6))
        let service: any ReferenceColorRasterServing = ReferenceColorRasterService()
        let result = try await service.prepare(document: source, logicalHeight: 2.1)
        XCTAssertEqual(result.referenceSize, try .init(width: 3, height: 2))
        XCTAssertEqual(result.raster.size, try .init(width: 4, height: 3))
        XCTAssertEqual(result.displayImage.width, 4)
        XCTAssertEqual(result.displayImage.height, 3)
        for height in [0, -1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            XCTAssertThrowsError(try ReferenceColorRasterCodec.prepare(document: source, logicalHeight: height)) {
                XCTAssertEqual($0 as? ReferenceColorRasterError, .invalidLogicalHeight)
            }
        }
        XCTAssertThrowsError(try ReferenceColorRasterCodec.prepare(document: source, logicalHeight: 6000)) {
            XCTAssertEqual($0 as? ReferenceColorRasterError, .fittedLimitExceeded)
        }
    }
}
