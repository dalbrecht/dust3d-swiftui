import Dust3DDocument
import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

final class SourceBakedLoaderTests: XCTestCase {
    func testPinsProceduralImagesAndCopiesStraightAlphaRows() throws {
        let imageID = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let xml =
            "<canvas originX='0' originY='0' originZ='0'><nodes><node id='{11111111-1111-4111-8111-111111111111}' partId='\(part)' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='\(part)'/></parts><components><component id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId' linkData='\(part)' color='#ffffff' colorImageId='\(imageID)'/></components></canvas>"
        let archive = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let image = MeshBakeImage(
            imageID: imageID, width: 1, height: 2, rowStride: 8,
            pixels: Data([255, 0, 0, 128, 99, 99, 99, 99, 0, 0, 255, 64]))
        let output = try MeshLoader.loadSourceBaked(data: archive, images: [image], options: smallOptions())
        let pixels = output.textures.color.pixels
        let expected: Set<[UInt8]> = [[255, 0, 0, 128], [0, 0, 255, 64]]
        var observed: Set<[UInt8]> = []
        for offset in stride(from: 0, to: pixels.count, by: 4) { observed.insert(Array(pixels[offset..<offset + 4])) }
        XCTAssertEqual(observed, expected)
        XCTAssertThrowsError(try MeshLoader.loadSourceBaked(data: archive, options: smallOptions()))
        XCTAssertEqual(output.textures.color.pixels, pixels)
    }
    func testCopiesActualImportedSourcePolicyAndFactorsWithoutChangingArchive() throws {
        let archive = try fixture("ImportedSurface")
        let original = archive
        let definition = try XCTUnwrap(ImportedMaterialLoader.load(data: archive).models.first)
        let decoded = try ImportedImageDecoder.decode(try XCTUnwrap(definition.image), modelID: definition.id)
        let image = SourceMeshBakeImage(decodedImage: decoded)
        let result = try MeshLoader.loadSourceBaked(data: archive, modelImages: [image], options: smallOptions())
        XCTAssertEqual(result.geometry.triangleCount, 4)
        XCTAssertEqual(result.modelIDs.map(\.rawValue), [definition.id])
        XCTAssertEqual(result.triangles.count, 4)
        for triangle in result.triangles {
            XCTAssertNotNil(triangle.packedUVs)
            XCTAssertEqual(triangle.modelIndex, 0)
            XCTAssertNotNil(triangle.componentIndex)
            let policy = try XCTUnwrap(triangle.policy)
            XCTAssertEqual(policy.alphaMode, definition.alphaMode)
            XCTAssertEqual(policy.alphaCutoff, definition.alphaCutoff)
            XCTAssertEqual(policy.isDoubleSided, definition.isDoubleSided)
        }
        XCTAssertTrue(result.geometry.vertices.allSatisfy { $0.color == SIMD4<Float>(repeating: 1) })
        XCTAssertEqual(try XCTUnwrap(result.textures.metallic).pixels.first, 32)
        XCTAssertEqual(try XCTUnwrap(result.textures.roughness).pixels.first, 159)
        XCTAssertEqual(result.maximumSamplingLod, 0)
        XCTAssertEqual(archive, original)
        XCTAssertThrowsError(try MeshLoader.loadSourceBaked(data: archive, options: smallOptions())) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 2)
            XCTAssertTrue(($0 as? MeshLoadingError)?.message.contains("image") == true)
        }
    }

    func testIndependentNativeAndSwiftQuotasPreserveOriginalFailure() throws {
        let archive = try fixture("Capsule")
        let result = try MeshLoader.loadSourceBaked(data: archive, options: smallOptions())
        let exact = try MeshLoader.loadSourceBaked(
            data: archive, options: smallOptions(copy: result.copiedPayloadBytes))
        XCTAssertEqual(exact.copiedPayloadBytes, result.copiedPayloadBytes)
        XCTAssertThrowsError(
            try MeshLoader.loadSourceBaked(data: archive, options: smallOptions(copy: result.copiedPayloadBytes - 1))
        ) {
            XCTAssertEqual($0 as? SourceMeshBakeError, .copyLimitExceeded)
        }
        XCTAssertThrowsError(
            try MeshLoader.loadSourceBaked(
                data: archive, options: SourceMeshBakeOptions(bake: smallOptions().bake, maximumNativePayloadBytes: 1))
        ) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 4)
            XCTAssertFalse(($0 as? MeshLoadingError)?.message.isEmpty ?? true)
        }
        XCTAssertThrowsError(try MeshLoader.loadSourceBaked(data: Data(), options: smallOptions())) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 1)
        }
    }

    func testRejectsMalformedModelImagesAndBoundsActualCombinedStorage() throws {
        let bytes = Data([1, 2, 3, 4])
        for image in [
            SourceMeshBakeImage(modelID: "", width: 1, height: 1, rowStride: 4, pixels: bytes),
            SourceMeshBakeImage(modelID: "a\0b", width: 1, height: 1, rowStride: 4, pixels: bytes),
            SourceMeshBakeImage(
                modelID: String(repeating: "x", count: 129), width: 1, height: 1, rowStride: 4, pixels: bytes),
            SourceMeshBakeImage(modelID: "x", width: Int.max, height: 1, rowStride: 4, pixels: bytes),
            SourceMeshBakeImage(modelID: "x", width: 1, height: 0, rowStride: 4, pixels: bytes),
            SourceMeshBakeImage(modelID: "x", width: 1, height: 1, rowStride: 3, pixels: bytes),
            SourceMeshBakeImage(modelID: "x", width: 1, height: 2, rowStride: Int.max, pixels: bytes),
            SourceMeshBakeImage(modelID: "x", width: 1, height: 1, rowStride: 4, pixels: Data()),
        ] {
            XCTAssertThrowsError(try SourceMeshBakeInput.validateImages([image], legacy: [], maximumBytes: 32)) {
                XCTAssertEqual($0 as? SourceMeshBakeError, .invalidInputImage)
            }
        }
        let image = SourceMeshBakeImage(modelID: "x", width: 1, height: 1, rowStride: 4, pixels: bytes)
        XCTAssertThrowsError(try SourceMeshBakeInput.validateImages([image, image], legacy: [], maximumBytes: 32))
        XCTAssertThrowsError(
            try SourceMeshBakeInput.validateImages(
                Array(repeating: image, count: 10001), legacy: [], maximumBytes: 100000))
        let legacy = MeshBakeImage(imageID: "unused", width: 1, height: 1, rowStride: 4, pixels: bytes)
        XCTAssertThrowsError(try SourceMeshBakeInput.validateImages([image], legacy: [legacy], maximumBytes: 7)) {
            XCTAssertEqual($0 as? SourceMeshBakeError, .inputLimitExceeded)
        }
        try SourceMeshBakeInput.validateImages([image], legacy: [legacy], maximumBytes: 8)
        let decomposed = SourceMeshBakeImage(modelID: "e\u{301}", width: 1, height: 1, rowStride: 4, pixels: bytes)
        let composed = SourceMeshBakeImage(modelID: "é", width: 1, height: 1, rowStride: 4, pixels: bytes)
        try SourceMeshBakeInput.validateImages([decomposed, composed], legacy: [], maximumBytes: 8)
    }
    func testOwnsProceduralGeometryAndMapsAfterNativeOwnerIsDestroyed() throws {
        let archive = try Data(
            contentsOf: XCTUnwrap(
                Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures")))
        let options = SourceMeshBakeOptions(bake: MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8))
        let output = try MeshLoader.loadSourceBaked(data: archive, options: options)
        XCTAssertEqual(output.triangles.count * 3, output.geometry.vertices.count)
        XCTAssertEqual(output.maximumSamplingLod, 0)
        XCTAssertEqual(output.textures.color.pixels.count, 256)
        XCTAssertNotNil(output.textures.metallic)
        XCTAssertNotNil(output.textures.roughness)
        XCTAssertNotNil(output.textures.emissive)
        XCTAssertGreaterThan(output.nativePayloadBytes, 0)
        XCTAssertGreaterThan(output.copiedPayloadBytes, 0)
        let pixels = output.textures.color.pixels
        _ = try MeshLoader.loadSourceBaked(data: archive, options: options)
        XCTAssertEqual(output.textures.color.pixels, pixels)
        XCTAssertTrue(output.triangles.contains { $0.packedUVs != nil })
    }

    func testRejectsInvalidInputLimitsBeforeNativeGeneration() throws {
        for options in [
            SourceMeshBakeOptions(maximumCopiedPayloadBytes: 0),
            SourceMeshBakeOptions(maximumNativePayloadBytes: -1),
            SourceMeshBakeOptions(maximumInputImageBytes: Int.max),
            SourceMeshBakeOptions(maximumChartCount: 100001),
            SourceMeshBakeOptions(maximumRasterSamples: -1),
        ] {
            XCTAssertThrowsError(try SourceMeshBakeInput.validate(dataCount: 1, options: options)) {
                XCTAssertEqual($0 as? SourceMeshBakeError, .invalidLimits)
            }
        }
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures")))
    }

    private func smallOptions(copy: Int = 8 * 1024 * 1024) -> SourceMeshBakeOptions {
        SourceMeshBakeOptions(
            bake: MeshBakeOptions(colorSize: 256, normalSize: 128, materialSize: 256, atlasTextureSize: 256),
            maximumCopiedPayloadBytes: copy)
    }
}
