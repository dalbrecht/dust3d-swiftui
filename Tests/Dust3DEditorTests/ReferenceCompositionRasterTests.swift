import CoreGraphics
import CryptoKit
import Dust3DEditorModel
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Dust3DEditor

final class ReferenceCompositionRasterTests: XCTestCase {
    private func stripes() throws -> CGImage {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(
            CGImage(
                width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }
    func testRasterCropUsesTopLeftRowsWhiteBackgroundAndPNG() throws {
        let image = try stripes()
        let size = try ReferencePixelSize(width: 2, height: 2)
        let crop = try ReferenceImageCrop(size: size, x: 0, y: 0, width: 2, height: 1)
        let source = try ReferenceCompositionSource(image: image, crop: crop)
        let result = try ReferenceCompositionRaster.compose(front: source, side: nil)
        XCTAssertEqual(result.layout.width, 2048)
        let decoded = try ReferenceImageCodec.decodePNG(result.png)
        XCTAssertEqual(decoded.width, 2048)
        XCTAssertEqual(decoded.height, 512)
        XCTAssertEqual(try pixel(decoded, x: 128, y: 256), [255, 0, 0, 255])
        XCTAssertEqual(try pixel(decoded, x: 896, y: 256), [0, 255, 0, 255])
        XCTAssertEqual(try pixel(decoded, x: 1536, y: 256), [255, 255, 255, 255])
    }
    func testFixedPointCompositionMatchesQtSmoothResampling() throws {
        let fixtures = [
            (7, 9, false, "dfa3aa5112e22b45b802a1b7571b909d932a8d11e897e84793b1b963a53ab285"),
            (701, 893, false, "8e60941b7a02883089cf39cb089103459ee72e44df8c15137685e4e3c676d2e8"),
            (453, 1201, false, "ba151442bb927afcf199e46f2ac946ee7746617d242877dddd9341d0a5587af6"),
            (453, 1201, true, "a3dc2fbddbbee758acac0856d32750d694c336da9bc7ece0edff7daf764cfdce"),
        ]
        for (width, height, hasAlpha, expected) in fixtures {
            var bytes = Data(capacity: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    bytes.append(UInt8((x * 71 + y * 13) % 256))
                    bytes.append(UInt8((x * 23 + y * 29) % 256))
                    bytes.append(UInt8((x * 97 + y * 7) % 256))
                    bytes.append(hasAlpha ? UInt8((x * 19 + y * 83) % 256) : 255)
                }
            }
            var preview = bytes
            if hasAlpha {
                for offset in stride(from: 0, to: preview.count, by: 4) {
                    for channel in 0..<3 {
                        preview[offset + channel] = UInt8(
                            (Int(bytes[offset + channel]) * Int(bytes[offset + 3]) + 127) / 255)
                    }
                }
            }
            let provider = try XCTUnwrap(CGDataProvider(data: preview as CFData))
            let image = try XCTUnwrap(
                CGImage(
                    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: width * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                    bitmapInfo: CGBitmapInfo(
                        rawValue: (hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let source = try ReferenceCompositionSource(
                image: image, crop: .init(size: .init(width: width, height: height)),
                straightRGBA: hasAlpha ? bytes : nil)
            let result = try ReferenceCompositionRaster.compose(front: source, side: nil)
            let rgba = try XCTUnwrap(result.image.dataProvider?.data) as Data
            let digest = SHA256.hash(data: rgba).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected, "\(width) × \(height)")
        }
    }

    func testServiceImportsNormalizedPixelsAndComposesOnItsActor() async throws {
        let image = try stripes()
        let png = try ReferenceImageCodec.encodePNG(image)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("composition-\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let service = ReferenceCompositionService()
        let imported = try await service.importSource(url: url)
        XCTAssertEqual(imported.crop, .init(size: try .init(width: 2, height: 2)))
        XCTAssertFalse(imported.isMirrored)
        let result = try await service.compose(front: imported, side: imported)
        XCTAssertEqual(result.layout.width, 1024)
        XCTAssertEqual(try ReferenceImageCodec.decodePNG(result.png).height, 512)
    }

    func testCompositionImportRetainsStraightPNGChannels() async throws {
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGklEQVR4nGNYYnWOnZmFlYFBwaGB5ZcS638AJsMExMfuGgkAAAAASUVORK5CYII="
            ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "straight-reference-\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let source = try await ReferenceCompositionService().importSource(url: url)
        XCTAssertEqual(
            source.straightRGBA,
            Data([
                164, 58, 206, 7, 3, 4, 5, 0, 32, 64, 128, 4, 250, 34, 5, 255,
            ]))
    }

    func testTaggedWideGamutImportKeepsColorManagedRendering() async throws {
        let source = try await importTaggedPNG(colorSpace: CGColorSpace.displayP3, orientation: 1)
        XCTAssertEqual(source.image.width, 2)
        XCTAssertEqual(source.image.height, 1)
        XCTAssertNil(source.straightRGBA)
    }

    func testOrientationTaggedImportKeepsNormalizedCoordinates() async throws {
        let source = try await importTaggedPNG(colorSpace: CGColorSpace.sRGB, orientation: 6)
        XCTAssertEqual(source.image.width, 1)
        XCTAssertEqual(source.image.height, 2)
        XCTAssertNil(source.straightRGBA)
    }

    private func importTaggedPNG(colorSpace: CFString, orientation: Int) async throws -> ReferenceCompositionSource {
        let space = try XCTUnwrap(CGColorSpace(name: colorSpace))
        let provider = try XCTUnwrap(CGDataProvider(data: Data([96, 10, 20, 128, 21, 80, 35, 128]) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tagged-reference-\(UUID().uuidString).png")
        try (output as Data).write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return try await ReferenceCompositionService().importSource(url: url)
    }

    func testSideMirrorAndSourceSizeMismatch() throws {
        let image = try stripes()
        let crop = ReferenceImageCrop(size: try ReferencePixelSize(width: 2, height: 2))
        let source = try ReferenceCompositionSource(image: image, crop: crop, isMirrored: true)
        let result = try ReferenceCompositionRaster.compose(front: nil, side: source)
        let decoded = try ReferenceImageCodec.decodePNG(result.png)
        XCTAssertEqual(try pixel(decoded, x: 128, y: 128), [255, 255, 255, 255])
        XCTAssertEqual(try pixel(decoded, x: 576, y: 64), [0, 255, 0, 255])
        XCTAssertEqual(try pixel(decoded, x: 960, y: 448), [0, 0, 255, 255])
        let wrong = ReferenceImageCrop(size: try ReferencePixelSize(width: 1, height: 1))
        XCTAssertThrowsError(try ReferenceCompositionSource(image: image, crop: wrong))
        XCTAssertThrowsError(try ReferenceCompositionRaster.compose(front: nil, side: nil))
    }
}
