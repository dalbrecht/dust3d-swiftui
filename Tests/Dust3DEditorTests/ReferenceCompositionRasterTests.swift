import CoreGraphics
import Dust3DEditorModel
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
