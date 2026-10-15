import CoreGraphics
import Dust3DDocument
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Dust3DEditor

final class ReferenceImageCodecTests: XCTestCase {
    private func imageData(type: UTType = .png, width: Int = 2, height: Int = 3, orientation: Int? = nil) throws -> Data
    {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image, orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary })
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
    func testSupportedRasterFormatsConvertToBoundedPNG() throws {
        for type in [UTType.png, .jpeg, .bmp, .gif, .tiff] {
            let input = try imageData(type: type)
            let png = try ReferenceImageCodec.importPNG(input)
            XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
            let decoded = try ReferenceImageCodec.decodePNG(png)
            XCTAssertEqual(decoded.width, 2)
            XCTAssertEqual(decoded.height, 3)
        }
    }
    func testInvalidAndEncodedOversizedInputsReject() {
        for invalid in [Data(), Data("invalid".utf8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])] {
            XCTAssertThrowsError(try ReferenceImageCodec.importPNG(invalid))
        }
        XCTAssertThrowsError(try ReferenceImageCodec.importPNG(Data(repeating: 0, count: 32 * 1024 * 1024 + 1))) {
            XCTAssertEqual($0 as? ReferenceImageError, .imageTooLarge)
        }
    }
    func testDimensionsAndPixelProductAreValidatedBeforeDecode() throws {
        XCTAssertNoThrow(try ReferenceImageCodec.validateDimensions(width: 4096, height: 4096))
        XCTAssertNoThrow(try ReferenceImageCodec.validateDimensions(width: 8192, height: 1))
        for dimensions in [(0, 1), (1, 0), (-1, 1), (8193, 1), (1, 8193), (8192, 4096)] {
            XCTAssertThrowsError(try ReferenceImageCodec.validateDimensions(width: dimensions.0, height: dimensions.1))
            {
                XCTAssertEqual($0 as? ReferenceImageError, .imageTooLarge)
            }
        }
        let image = try imageData(width: 8193, height: 1)
        XCTAssertThrowsError(try ReferenceImageCodec.importPNG(image))
    }
    func testExistingPNGPreviewDoesNotReencodeArchiveBytesAndCachesImage() async throws {
        let image = try imageData()
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(.setReferenceImagePNG(image))
        let service = ReferenceImageService()
        let first = try await service.preview(document: original)
        XCTAssertNotNil(first.image)
        XCTAssertTrue(first.changed)
        let cached = try await service.preview(document: original)
        XCTAssertTrue(first.image === cached.image)
        XCTAssertFalse(cached.changed)
        XCTAssertEqual(original.referenceImagePNG, image)
        let blank = try original.applying(.setReferenceImagePNG(nil))
        let cleared = try await service.preview(document: blank)
        XCTAssertNil(cleared.image)
        XCTAssertTrue(cleared.changed)
    }
    func testImportedOrientationIsBakedIntoPNGDimensions() throws {
        let jpeg = try imageData(type: .jpeg, orientation: 6)
        let png = try ReferenceImageCodec.importPNG(jpeg)
        let image = try ReferenceImageCodec.decodePNG(png)
        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 2)
    }
    func testFileImportReportsSizeTypeAndReadFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ReferenceImageService()
        let url = directory.appendingPathComponent("reference.png")
        try imageData().write(to: url)
        let output = try await service.importImage(url: url)
        XCTAssertEqual(try ReferenceImageCodec.decodePNG(output).height, 3)
        do {
            _ = try await service.importImage(url: directory)
            XCTFail("Directories are not raster files")
        } catch {
            XCTAssertEqual(error as? ReferenceImageError, .invalidImage)
        }
        do {
            _ = try await service.importImage(url: directory.appendingPathComponent("missing.png"))
            XCTFail("Missing input must fail")
        } catch {
            guard case .fileReadFailed(let cause) = error as? ReferenceImageError else {
                return XCTFail("Original read cause must be retained")
            }
            XCTAssertFalse(cause.isEmpty)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(32 * 1024 * 1024 + 1))
        try handle.close()
        do {
            _ = try await service.importImage(url: url)
            XCTFail("Oversized files must reject before reading")
        } catch {
            XCTAssertEqual(error as? ReferenceImageError, .imageTooLarge)
        }
    }
    func testPNGPreviewRejectsOtherFormatsAndMalformedPreservedAsset() throws {
        XCTAssertThrowsError(try ReferenceImageCodec.decodePNG(imageData(type: .jpeg))) {
            XCTAssertEqual($0 as? ReferenceImageError, .unsupportedFormat)
        }
        XCTAssertThrowsError(try ReferenceImageCodec.decodePNG(Data("not image".utf8)))
    }

    func testOversizedExistingAssetRejectsFromMetadataAndRemainsPreserved() async throws {
        let model = Data("<canvas/>".utf8)
        let oversized = Data(repeating: 0, count: 32 * 1024 * 1024 + 1)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='canvas.png' offset='\(model.count)' size='\(oversized.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let bytes =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model + oversized
        let document = try Dust3DDocument(data: bytes)
        XCTAssertTrue(document.hasReferenceImage)
        XCTAssertEqual(document.referenceImageByteCount, oversized.count)
        do {
            _ = try await ReferenceImageService().preview(document: document)
            XCTFail("Oversized existing references must not be decoded")
        } catch {
            XCTAssertEqual(error as? ReferenceImageError, .imageTooLarge)
        }
        XCTAssertEqual(document.encoded(), bytes)
    }
}
