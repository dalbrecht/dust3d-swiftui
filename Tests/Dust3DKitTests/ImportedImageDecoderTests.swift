import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class ImportedImageDecoderTests: XCTestCase {
    private func image(_ name: String, encoding: ImportedImageEncoding) throws -> ImportedEncodedImage {
        let suffix = encoding == .png ? "png" : "jpg"
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: suffix, subdirectory: "Fixtures"))
        return ImportedEncodedImage(encoding: encoding, bytes: try Data(contentsOf: url))
    }

    func test_should_preserve_png_straight_alpha_and_original_model_identity() throws {
        let decoded = try ImportedImageDecoder.decode(try image("ImportedMaterial", encoding: .png), modelID: "Model")
        XCTAssertEqual(decoded.modelID, "Model")
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(decoded.rowStride, 8)
        XCTAssertEqual(Array(decoded.pixels), [255, 0, 0, 128, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 64])
    }

    func test_should_decode_baseline_progressive_and_gray_jpeg_as_opaque_rgba() throws {
        for name in ["ImportedMaterial", "ImportedProgressive", "ImportedGray"] {
            let decoded = try ImportedImageDecoder.decode(try image(name, encoding: .jpeg), modelID: name)
            XCTAssertEqual(decoded.modelID, name)
            XCTAssertEqual(decoded.width, 2)
            XCTAssertEqual(decoded.height, 2)
            XCTAssertEqual(decoded.rowStride, 8)
            XCTAssertEqual(decoded.pixels.count, 16)
            for offset in stride(from: 3, to: 16, by: 4) { XCTAssertEqual(decoded.pixels[offset], 255) }
            if name == "ImportedGray" {
                for offset in stride(from: 0, to: 16, by: 4) {
                    XCTAssertEqual(decoded.pixels[offset], decoded.pixels[offset + 1])
                    XCTAssertEqual(decoded.pixels[offset], decoded.pixels[offset + 2])
                }
            }
        }
    }

    func test_should_reject_declared_format_mismatch_and_size_limits() throws {
        let png = try image("ImportedMaterial", encoding: .png)
        XCTAssertThrowsError(try ImportedImageDecoder.decode(.init(encoding: .jpeg, bytes: png.bytes), modelID: "M")) {
            XCTAssertEqual($0 as? JPEGContainerError, .invalidJPEG)
        }
        let jpeg = try image("ImportedMaterial", encoding: .jpeg)
        XCTAssertThrowsError(try ImportedImageDecoder.decode(.init(encoding: .png, bytes: jpeg.bytes), modelID: "M")) {
            XCTAssertEqual($0 as? MeshPNGDecodingError, .invalidPNG)
        }
        XCTAssertThrowsError(try ImportedImageDecoder.decode(jpeg, modelID: "M", maximumDecodedBytes: 15)) {
            XCTAssertEqual($0 as? JPEGContainerError, .decodedLimitExceeded)
        }
        XCTAssertThrowsError(try ImportedImageDecoder.decode(jpeg, modelID: "M", maximumEncodedBytes: 1)) {
            XCTAssertEqual($0 as? JPEGContainerError, .encodedLimitExceeded)
        }
    }

    func test_should_decode_on_background_service_and_respect_cancellation() async throws {
        let source = try image("ImportedMaterial", encoding: .jpeg)
        let service = ImportedMaterialService()
        let decoded = try await service.decodeImage(source, modelID: "M")
        XCTAssertEqual(decoded.pixels.count, 16)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.decodeImage(source, modelID: "M")
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled image decode must not publish pixels")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
    func test_should_reject_unsupported_cmyk_pixels_and_structurally_valid_but_undecodable_stream() throws {
        XCTAssertThrowsError(try ImportedImageDecoder.decode(try image("ImportedCMYK", encoding: .jpeg), modelID: "M"))
        {
            XCTAssertEqual($0 as? MeshJPEGDecodingError, .unsupportedPixelLayout)
        }
        let bytes = Data([
            255, 216, 255, 192, 0, 11, 8, 0, 2, 0, 2, 1, 1, 17, 0,
            255, 218, 0, 8, 1, 1, 0, 0, 63, 0, 1, 255, 217,
        ])
        XCTAssertNoThrow(try JPEGContainerMetadata(data: bytes))
        XCTAssertThrowsError(try ImportedImageDecoder.decode(.init(encoding: .jpeg, bytes: bytes), modelID: "M")) {
            XCTAssertEqual($0 as? MeshJPEGDecodingError, .invalidJPEG)
        }
    }

}
