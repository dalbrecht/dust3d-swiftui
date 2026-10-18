import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

final class ArchiveTextureBakingServiceTests: XCTestCase {
    func test_should_publish_actionable_archive_and_png_diagnostics() {
        let pngErrors: [(MeshPNGDecodingError, String)] = [
            (.invalidLimits, "limits"), (.encodedLimitExceeded, "encoded"), (.invalidPNG, "PNG"),
            (.decodedLimitExceeded, "decoded"), (.unsupportedPixelLayout, "pixel"),
        ]
        for (cause, expected) in pngErrors {
            XCTAssertTrue(cause.localizedDescription.contains(expected))
            let wrapped = ArchiveTextureBakingError.imageDecoding(assetName: "images/broken.png", cause: cause)
            XCTAssertTrue(wrapped.localizedDescription.contains("images/broken.png"))
            XCTAssertTrue(wrapped.localizedDescription.contains(cause.localizedDescription))
        }
        for (cause, expected) in [
            (ArchiveTextureBakingError.invalidLimits, "limits"),
            (.encodedLimitExceeded, "encoded"), (.decodedLimitExceeded, "decoded"),
            (.missingAsset("images/missing.png"), "images/missing.png"),
        ] {
            XCTAssertTrue(cause.localizedDescription.contains(expected))
        }
    }

    func test_should_bake_retained_png_without_modifying_archive_assets() async throws {
        let bytes = try archive()
        let document = try Dust3DDocument(data: bytes)
        let result = try await ArchiveTextureBakingService().load(
            data: bytes, options: MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8))
        let expected: Set<[UInt8]> = [[255, 0, 0, 128], [0, 0, 255, 1]]
        var observed: Set<[UInt8]> = []
        for offset in stride(from: 0, to: result.textures.color.pixels.count, by: 4) {
            observed.insert(Array(result.textures.color.pixels[offset..<offset + 4]))
        }
        XCTAssertEqual(observed, expected)
        XCTAssertEqual(document.encoded(), bytes)
        XCTAssertEqual(document.asset(named: "opaque.bin"), Data([19, 20, 21]))
    }

    func test_should_enforce_aggregate_budgets_and_keep_decode_cause() async throws {
        let bytes = try archive()
        for limits in [
            ArchiveTextureLimits(maximumEncodedImageBytes: 1),
            ArchiveTextureLimits(maximumEncodedTotalBytes: 1),
            ArchiveTextureLimits(maximumDecodedTotalBytes: 7),
            ArchiveTextureLimits(maximumEncodedImageBytes: 0),
        ] {
            do {
                _ = try await ArchiveTextureBakingService().load(data: bytes, limits: limits)
                XCTFail("Expected resource-limit failure")
            } catch { XCTAssertTrue(error is ArchiveTextureBakingError) }
        }
        do {
            _ = try await ArchiveTextureBakingService().load(data: archive(png: Data([1, 2, 3])))
            XCTFail("Expected PNG failure")
        } catch {
            XCTAssertEqual(
                error as? ArchiveTextureBakingError, .imageDecoding(assetName: assetName, cause: .invalidPNG))
        }
    }

    func test_should_apply_totals_across_distinct_images_and_accept_exact_budget() async throws {
        let bytes = try archive(secondImage: true)
        let document = try Dust3DDocument(data: bytes)
        let totalEncoded = try document.textureImageReferences().reduce(0) { $0 + $1.encodedByteCount }
        for (limits, expected) in [
            (
                ArchiveTextureLimits(maximumEncodedTotalBytes: totalEncoded - 1),
                ArchiveTextureBakingError.encodedLimitExceeded
            ),
            (ArchiveTextureLimits(maximumDecodedTotalBytes: 8), .decodedLimitExceeded),
            (
                ArchiveTextureLimits(maximumDecodedTotalBytes: 15),
                .imageDecoding(assetName: secondAssetName, cause: .decodedLimitExceeded)
            ),
        ] {
            do {
                _ = try await ArchiveTextureBakingService().load(data: bytes, limits: limits)
                XCTFail("Expected aggregate resource limit")
            } catch { XCTAssertEqual(error as? ArchiveTextureBakingError, expected) }
        }
        let output = try await ArchiveTextureBakingService().load(
            data: bytes, options: MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8),
            limits: ArchiveTextureLimits(maximumEncodedTotalBytes: totalEncoded, maximumDecodedTotalBytes: 16))
        XCTAssertEqual(output.textures.color.pixels.count, 256)
    }

    func test_should_reject_cancelled_archive_bake_before_loading() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ArchiveTextureBakingService().load(data: Data())
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private var imageID: String { "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}" }
    private var assetName: String { "images/\(imageID).png" }

    private var secondAssetName: String { "images/{jjjjjjjj-jjjj-jjjj-jjjj-jjjjjjjjjjjj}.png" }

    private func archive(png: Data? = nil, secondImage: Bool = false) throws -> Data {
        let encoded =
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
        let image = try png ?? XCTUnwrap(Data(base64Encoded: encoded))
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let extraComponent =
            secondImage
            ? "<component id='{dddddddd-dddd-4ddd-8ddd-dddddddddddd}' colorImageId='{jjjjjjjj-jjjj-jjjj-jjjj-jjjjjjjjjjjj}'/>"
            : ""
        let xml =
            "<canvas originX='0' originY='0' originZ='0'><nodes><node id='{11111111-1111-4111-8111-111111111111}' partId='\(part)' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='\(part)'/></parts><components><component id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId' linkData='\(part)' color='#ffffff' colorImageId='\(imageID)'/>\(extraComponent)</components></canvas>"
        let model = Data(xml.utf8)
        let opaque = Data([19, 20, 21])
        let extraHeader =
            secondImage
            ? "<asset name='\(secondAssetName)' offset='\(model.count + image.count + opaque.count)' size='\(image.count)'/>"
            : ""
        let header = Data(
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='\(assetName)' offset='\(model.count)' size='\(image.count)'/><asset name='opaque.bin' offset='\(model.count + image.count)' size='3'/>\(extraHeader)</ds3>"
                .utf8)
        let prefix = Data("DUST3D 1.0 xml \(String(format: "%010d", 26 + header.count))\n".utf8)
        return prefix + header + model + image + opaque + (secondImage ? image : Data())
    }
}
