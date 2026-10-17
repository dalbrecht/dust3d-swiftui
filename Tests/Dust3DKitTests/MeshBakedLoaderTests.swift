import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

final class MeshBakedLoaderTests: XCTestCase {
    func testCopiesActualBakedOutputWithoutSharingTexturedCorners() throws {
        for name in ["Capsule", "Sword", "RoundedCrossing"] {
            let data = try fixture(name)
            let options = MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8)
            let result = try MeshLoader.loadBaked(data: data, options: options)
            XCTAssertEqual(result.geometry.vertices.count, result.metadata.triangles.count * 3)
            XCTAssertEqual(result.tangents.count, result.metadata.triangles.count)
            XCTAssertEqual(result.textures.color.width, 8)
            XCTAssertEqual(result.textures.color.height, 8)
            XCTAssertEqual(result.textures.color.rowStride, 32)
            XCTAssertEqual(result.textures.color.pixels.count, 256)
            XCTAssertNil(result.textures.normal)
            let pixels = result.textures.color.pixels
            let positions = result.geometry.vertices.map(\.position)
            _ = try MeshLoader.loadBaked(data: fixture("Sword"), options: options)
            XCTAssertEqual(result.textures.color.pixels, pixels)
            XCTAssertEqual(result.geometry.vertices.map(\.position), positions)
            for (index, tangent) in result.tangents.enumerated() {
                XCTAssertTrue(
                    tangent.direction.x.isFinite && tangent.direction.y.isFinite && tangent.direction.z.isFinite)
                if tangent.hasMapping { XCTAssertTrue(result.metadata.triangles[index].hasMapping) }
            }
        }
    }

    func testRejectsInvalidDimensionsAndPreservesNativeQuotaCauses() throws {
        let data = try fixture("Capsule")
        for size in [-1, 0, 8193] {
            XCTAssertThrowsError(try MeshLoader.loadBaked(data: data, options: MeshBakeOptions(colorSize: size))) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
            }
        }
        let options = MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8, maximumBakePayloadBytes: 1)
        XCTAssertThrowsError(try MeshLoader.loadBaked(data: data, options: options)) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 4)
            XCTAssertFalse(($0 as? MeshLoadingError)?.message.isEmpty ?? true)
        }
        XCTAssertThrowsError(try MeshLoader.loadBaked(data: Data())) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
        }
    }

    func testPinsDecodedImageRowsAndCopiesMaterialAndAlphaOutput() throws {
        let imageID = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"
        let data = try archive(imageID: imageID)
        let pixels = Data([255, 0, 0, 128, 99, 99, 99, 99, 0, 0, 255, 64])
        let source = MeshBakeImage(imageID: imageID, width: 1, height: 2, rowStride: 8, pixels: pixels)
        let unused = MeshBakeImage(
            imageID: imageID.uppercased(), width: 1, height: 1, rowStride: 4, pixels: Data([0, 255, 0, 255]))
        let options = MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8)
        let result = try MeshLoader.loadBaked(data: data, images: [source, unused], options: options)
        let expected: Set<[UInt8]> = [[255, 0, 0, 128], [0, 0, 255, 64]]
        var observed: Set<[UInt8]> = []
        for offset in stride(from: 0, to: result.textures.color.pixels.count, by: 4) {
            let pixel = Array(result.textures.color.pixels[offset..<offset + 4])
            XCTAssertTrue(expected.contains(pixel))
            observed.insert(pixel)
        }
        XCTAssertEqual(observed, expected)
        XCTAssertEqual(try XCTUnwrap(result.textures.metallic).pixels.first, 128)
        XCTAssertEqual(try XCTUnwrap(result.textures.roughness).pixels.first, 64)
        XCTAssertEqual(try XCTUnwrap(result.textures.emissive).pixels.first, 255)
        XCTAssertThrowsError(try MeshLoader.loadBaked(data: data, options: options)) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 2)
            XCTAssertTrue(($0 as? MeshLoadingError)?.message.contains("image") == true)
        }
    }

    func testRejectsMalformedDecodedViewsAndAliasesBeforeNativeLoading() throws {
        let data = try fixture("Capsule")
        let key = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"
        let pixels = Data([1, 2, 3, 4])
        let invalid = [
            MeshBakeImage(imageID: "bad", width: 1, height: 1, rowStride: 4, pixels: pixels),
            MeshBakeImage(imageID: key, width: Int.max, height: 1, rowStride: 4, pixels: pixels),
            MeshBakeImage(imageID: key, width: 1, height: 0, rowStride: 4, pixels: pixels),
            MeshBakeImage(imageID: key, width: 1, height: 1, rowStride: 3, pixels: pixels),
            MeshBakeImage(imageID: key, width: 1, height: 1, rowStride: 4, pixels: Data()),
            MeshBakeImage(imageID: key, width: 1, height: 2, rowStride: Int.max, pixels: pixels),
        ]
        for image in invalid {
            XCTAssertThrowsError(try MeshLoader.loadBaked(data: data, images: [image])) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
            }
        }
        let image = MeshBakeImage(imageID: key, width: 1, height: 1, rowStride: 4, pixels: pixels)
        let alias = MeshBakeImage(
            imageID: String(key.dropFirst().dropLast()), width: 1, height: 1, rowStride: 4, pixels: pixels)
        XCTAssertThrowsError(try MeshLoader.loadBaked(data: data, images: [image, alias]))
        XCTAssertThrowsError(try MeshBakedInput.descriptors(Array(repeating: image, count: 10001)))
    }

    func testValidatesEveryResourceLimitBeforeNativeConversion() throws {
        for options in [
            MeshBakeOptions(normalSize: 0), MeshBakeOptions(materialSize: Int.max),
            MeshBakeOptions(atlasTextureSize: -1), MeshBakeOptions(maximumMetadataPayloadBytes: -1),
            MeshBakeOptions(maximumBakePayloadBytes: Int.min), MeshBakeOptions(maximumSpatialGridEntries: -1),
            MeshBakeOptions(maximumSpatialGridEntries: 16_000_001),
        ] {
            XCTAssertThrowsError(try MeshBakedInput.validate(dataCount: 1, options: options)) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
            }
        }
        for options in [
            MeshBakeOptions(maximumMetadataPayloadBytes: 268_435_457),
            MeshBakeOptions(maximumBakePayloadBytes: Int.max),
        ] {
            XCTAssertThrowsError(try MeshBakedInput.validate(dataCount: 1, options: options)) {
                XCTAssertEqual(($0 as? MeshLoadingError)?.status, 4)
            }
        }
        XCTAssertThrowsError(try MeshBakedInput.validate(dataCount: Int.max, options: MeshBakeOptions()))
        try MeshBakedInput.validate(dataCount: 1, options: MeshBakeOptions(maximumSpatialGridEntries: 16_000_000))
    }

    private func archive(imageID: String) throws -> Data {
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let xml =
            "<canvas originX='0' originY='0' originZ='0'><nodes><node id='{11111111-1111-4111-8111-111111111111}' partId='\(part)' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='\(part)' metallic='.5' roughness='.25' emissive='2'/></parts><components><component id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId' linkData='\(part)' color='#ffffff' colorImageId='\(imageID)'/></components></canvas>"
        return try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures")))
    }
}
