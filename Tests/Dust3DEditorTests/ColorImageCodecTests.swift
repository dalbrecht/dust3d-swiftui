import CoreGraphics
import Dust3DKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Dust3DEditor

final class ColorImageCodecTests: XCTestCase {
    private func imageData(type: UTType = .png, orientation: Int? = nil) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, try XCTUnwrap(context.makeImage()),
            orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary })
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testPNGImportPreservesOriginalBytesAndValidatesPixels() throws {
        let original = try imageData()
        XCTAssertEqual(try ColorImageCodec.prepare(original), original)
        let decoded = try MeshPNGDecoder.decode(original, imageID: "test")
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 3)
        XCTAssertThrowsError(try ColorImageCodec.prepare(original.dropLast(20)))
    }

    func testSupportedRasterFormatsProduceDecodablePNG() throws {
        for type in [UTType.jpeg, .bmp, .gif, .tiff] {
            let png = try ColorImageCodec.prepare(imageData(type: type))
            let image = try MeshPNGDecoder.decode(png, imageID: "test")
            XCTAssertEqual(image.width, 2)
            XCTAssertEqual(image.height, 3)
        }
    }

    func testMaterialImportKeepsEncodedOrientationInsteadOfCanvasTransform() throws {
        let png = try ColorImageCodec.prepare(imageData(type: .jpeg, orientation: 6))
        let image = try MeshPNGDecoder.decode(png, imageID: "test")
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 3)
    }

    func testDimensionLimitsRejectBeforePixelAllocation() throws {
        XCTAssertNoThrow(try ColorImageCodec.validateDimensions(width: 8192, height: 8192))
        for (width, height) in [(0, 1), (1, 0), (-1, 1), (8193, 1), (1, 8193), (Int.max, Int.max)] {
            XCTAssertThrowsError(try ColorImageCodec.validateDimensions(width: width, height: height)) {
                XCTAssertEqual($0 as? ColorImageError, .imageTooLarge)
            }
        }
    }

    func testInvalidImagesAndEncodedQuotaReject() {
        for data in [Data(), Data("not an image".utf8), Data(repeating: 0, count: 32 * 1024 * 1024 + 1)] {
            XCTAssertThrowsError(try ColorImageCodec.prepare(data))
        }
    }

    func testFileServiceRejectsRemoteURLsAndDirectoriesAndRetainsReadCause() async throws {
        let service = ColorImageService()
        do {
            _ = try await service.importImage(url: XCTUnwrap(URL(string: "https://example.com/image.png")))
            XCTFail("Remote resources must not be fetched")
        } catch { XCTAssertEqual(error as? ColorImageError, .invalidFile) }
        do {
            _ = try await service.importImage(url: FileManager.default.temporaryDirectory)
            XCTFail("Directories are not images")
        } catch { XCTAssertEqual(error as? ColorImageError, .invalidFile) }
        do {
            _ = try await service.importImage(
                url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            XCTFail("Missing files must report their cause")
        } catch {
            guard let failure = error as? ColorImageReadError else {
                return XCTFail("Expected retained read cause: \(error)")
            }
            XCTAssertFalse(failure.cause.localizedDescription.isEmpty)
        }
    }

    func testFileDecodeFailureRetainsInputNameAndOriginalCause() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not pixels".utf8).write(to: url)
        do {
            _ = try await ColorImageService().importImage(url: url)
            XCTFail("Invalid pixels must fail before publication")
        } catch {
            let failure = try XCTUnwrap(error as? ColorImagePreparationError)
            XCTAssertEqual(failure.fileName, url.lastPathComponent)
            XCTAssertEqual(failure.cause as? ColorImageError, .invalidImage)
            XCTAssertTrue(failure.localizedDescription.contains(url.lastPathComponent))
        }
    }

    func testFileServicePreservesPNGAndRejectsCancelledRequests() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let png = try imageData()
        try png.write(to: url)
        let service = ColorImageService()
        let imported = try await service.importImage(url: url)
        XCTAssertEqual(imported, png)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.importImage(url: url)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled import must not publish bytes")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
