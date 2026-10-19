import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class ArchiveSourceTextureBakingTests: XCTestCase {
    func testDecodesImportedPixelsFromSameArchiveAndReturnsOwnedBake() async throws {
        let archive = try fixture("ImportedSurface")
        let original = archive
        let result = try await ArchiveSourceTextureBakingService().load(data: archive, options: options())
        XCTAssertEqual(result.geometry.triangleCount, 4)
        XCTAssertEqual(result.modelIDs.map(\.rawValue), ["{00000300-0000-4000-8000-000000000300}"])
        XCTAssertEqual(try XCTUnwrap(result.textures.metallic).pixels.first, 32)
        XCTAssertEqual(try XCTUnwrap(result.textures.roughness).pixels.first, 159)
        XCTAssertEqual(result.maximumSamplingLod, 0)
        XCTAssertEqual(archive, original)
    }

    func testPreservesProceduralBakingWithoutImportedInputs() async throws {
        let result = try await ArchiveSourceTextureBakingService().load(data: fixture("Capsule"), options: options())
        XCTAssertEqual(result.geometry.triangleCount, 80)
        XCTAssertTrue(result.modelIDs.isEmpty)
        XCTAssertFalse(result.textures.color.pixels.isEmpty)
    }

    func testCombinesImportedAndProceduralInputsUnderOneBudgetWithoutRewritingAssets() async throws {
        let data = try mixedArchive()
        let document = try Dust3DDocument(data: data)
        let prepared = try ArchiveSourceImagePreparation.load(data: data, options: options(), limits: .init())
        XCTAssertEqual(prepared.models.count, 1)
        XCTAssertEqual(prepared.legacy.count, 1)
        XCTAssertEqual(prepared.models.first?.pixels.count, 16)
        XCTAssertEqual(prepared.legacy.first?.pixels.count, 8)
        let model = try XCTUnwrap(ImportedMaterialLoader.load(data: data).models.first)
        let encodedTotal =
            try XCTUnwrap(model.image).bytes.count
            + document.textureImageReferences().reduce(0) { $0 + $1.encodedByteCount }
        let exact = ArchiveSourceTextureLimits(
            textures: ArchiveTextureLimits(maximumEncodedTotalBytes: encodedTotal, maximumDecodedTotalBytes: 24))
        let output = try await ArchiveSourceTextureBakingService().load(
            data: data, options: options(input: 24), limits: exact)
        XCTAssertGreaterThan(output.geometry.triangleCount, 4)
        XCTAssertTrue(output.triangles.contains { $0.modelIndex == nil && $0.packedUVs != nil })
        XCTAssertTrue(output.triangles.contains { $0.modelIndex == 0 && $0.packedUVs != nil })
        XCTAssertEqual(document.encoded(), data)
        XCTAssertEqual(document.asset(named: "opaque.bin"), Data([19, 20, 21]))
        for limits in [
            ArchiveSourceTextureLimits(textures: ArchiveTextureLimits(maximumEncodedTotalBytes: encodedTotal - 1)),
            .init(textures: ArchiveTextureLimits(maximumEncodedImageBytes: 1)),
        ] {
            do {
                _ = try await ArchiveSourceTextureBakingService().load(data: data, options: options(), limits: limits)
                XCTFail("Encoded admission must reject")
            } catch { XCTAssertEqual(error as? ArchiveTextureBakingError, .encodedLimitExceeded) }
        }
        for (inputLimit, decodedLimit) in [(23, 24), (24, 23)] {
            do {
                _ = try await ArchiveSourceTextureBakingService().load(
                    data: data, options: options(input: inputLimit),
                    limits: .init(textures: ArchiveTextureLimits(maximumDecodedTotalBytes: decodedLimit)))
                XCTFail("Combined decoded storage must not exceed either quota")
            } catch let error as ArchiveSourceTextureBakingError {
                guard case .importedImageDecoding(let id, let cause) = error else {
                    return XCTFail("Expected contextual codec failure")
                }
                XCTAssertEqual(id, model.id)
                XCTAssertEqual(cause as? MeshPNGDecodingError, .decodedLimitExceeded)
                XCTAssertTrue(error.localizedDescription.contains(id))
                XCTAssertTrue(error.localizedDescription.contains(cause.localizedDescription))
            }
        }
        do {
            _ = try await ArchiveSourceTextureBakingService().load(data: data, options: options(input: 8))
            XCTFail("No decoded budget remains for the imported image")
        } catch { XCTAssertEqual(error as? ArchiveTextureBakingError, .decodedLimitExceeded) }
    }

    func testPreservesContextAndOriginalImportedPixelFailure() async throws {
        var data = try fixture("ImportedSurface")
        let model = try XCTUnwrap(ImportedMaterialLoader.load(data: data).models.first)
        let encoded = try XCTUnwrap(model.image).bytes
        let range = try XCTUnwrap(data.range(of: encoded))
        data[range.lowerBound] = 0
        do {
            _ = try await ArchiveSourceTextureBakingService().load(data: data, options: options())
            XCTFail("Corrupt imported PNG must reject")
        } catch let error as ArchiveSourceTextureBakingError {
            guard case .importedImageDecoding(let id, let cause) = error else {
                return XCTFail("Expected contextual codec failure")
            }
            XCTAssertEqual(id, model.id)
            XCTAssertEqual(cause as? MeshPNGDecodingError, .invalidPNG)
        }
    }

    func testValidatesLimitsAndPropagatesNativeFailureWithoutChangingIt() async throws {
        for limits in [
            ArchiveSourceTextureLimits(textures: ArchiveTextureLimits(maximumDecodedTotalBytes: 0)),
            .init(textures: ArchiveTextureLimits(maximumEncodedTotalBytes: Int.max)),
        ] {
            do {
                _ = try await ArchiveSourceTextureBakingService().load(data: Data(), limits: limits)
                XCTFail("Limits must reject before parsing")
            } catch { XCTAssertEqual(error as? ArchiveTextureBakingError, .invalidLimits) }
        }
        do {
            _ = try await ArchiveSourceTextureBakingService().load(
                data: fixture("ImportedSurface"),
                options: SourceMeshBakeOptions(bake: options().bake, maximumNativePayloadBytes: 1))
            XCTFail("Native output quota must reject")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 4)
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    func testCancelledRequestDoesNotParseOrPublish() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ArchiveSourceTextureBakingService().load(data: Data())
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled request must reject")
        } catch is CancellationError {}
    }

    func testTexturelessImportedMaterialDoesNotRequireDecodedPixels() async throws {
        var data = try fixture("ImportedSurface")
        let field = Data("\"baseColorTexture\":{\"index\":0},".utf8)
        let range = try XCTUnwrap(data.range(of: field))
        data.replaceSubrange(range, with: Data(repeating: 32, count: field.count))
        let prepared = try ArchiveSourceImagePreparation.load(data: data, options: options(), limits: .init())
        XCTAssertTrue(prepared.models.isEmpty)
        XCTAssertTrue(prepared.legacy.isEmpty)
        let output = try await ArchiveSourceTextureBakingService().load(data: data, options: options())
        XCTAssertEqual(output.geometry.triangleCount, 4)
        XCTAssertTrue(output.triangles.allSatisfy { $0.policy != nil && $0.packedUVs != nil })
    }

    func testCancellationAfterBakingCannotPublishAndOriginalBakerErrorsPropagate() async throws {
        let archive = try fixture("Capsule")
        let output = try MeshLoader.loadSourceBaked(data: archive, options: options())
        let service = ArchiveSourceTextureBakingService(baker: CancellingArchiveSourceBaker(output: output))
        let task = Task { try await service.load(data: archive, options: options()) }
        do {
            _ = try await task.value
            XCTFail("A cancelled successful bake must not publish")
        } catch is CancellationError {}
        do {
            _ = try await ArchiveSourceTextureBakingService(baker: FailingArchiveSourceBaker()).load(
                data: archive, options: options())
            XCTFail("Original baker failure must propagate")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 2)
            XCTAssertEqual(error.message, "original archive source failure")
        }
    }

    func testSharedImagePreparationPreservesMissingAssetCause() throws {
        let source = try Dust3DDocument(data: mixedArchive())
        let references = try source.textureImageReferences()
        let empty = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        var remaining = 1024
        XCTAssertThrowsError(
            try ArchiveTextureImagePreparation.decode(
                references, document: empty, maximumImageBytes: 1024, remainingDecoded: &remaining)
        ) {
            XCTAssertEqual($0 as? ArchiveTextureBakingError, .missingAsset(references[0].assetName))
        }
    }

    private func options(input: Int = 64 * 1024 * 1024) -> SourceMeshBakeOptions {
        SourceMeshBakeOptions(
            bake: MeshBakeOptions(colorSize: 256, normalSize: 128, materialSize: 256, atlasTextureSize: 256),
            maximumInputImageBytes: input)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures")))
    }

    private func mixedArchive() throws -> Data {
        let original = try Dust3DDocument(data: fixture("ImportedSurface"))
        var xml = try XCTUnwrap(String(data: original.modelXML, encoding: .utf8))
        let part = "{00000101-0000-4000-8000-000000000101}"
        let image = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"
        xml = xml.replacingOccurrences(of: "<component ", with: "<component combineMode='Uncombined' ")
            .replacingOccurrences(
                of: "</nodes>",
                with:
                    "<node id='{00001002-0000-4000-8000-000000001002}' partId='\(part)' x='3' y='3' z='3' radius='.1'/></nodes>"
            )
            .replacingOccurrences(of: "</parts>", with: "<part id='\(part)'/></parts>")
            .replacingOccurrences(
                of: "</components>",
                with:
                    "<component id='{00000201-0000-4000-8000-000000000201}' linkDataType='partId' linkData='\(part)' color='#ffffff' colorImageId='\(image)' combineMode='Uncombined'/></components>"
            )
        let modelName = "models/{00000300-0000-4000-8000-000000000300}.glb"
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
            ))
        let assets = [
            (modelName, try XCTUnwrap(original.asset(named: modelName))), ("images/\(image).png", png),
            ("opaque.bin", Data([19, 20, 21])),
        ]
        var payload = Data(xml.utf8)
        var header = "<ds3><model name='model.xml' offset='0' size='\(payload.count)'/>"
        for (name, bytes) in assets {
            header += "<asset name='\(name)' offset='\(payload.count)' size='\(bytes.count)'/>"
            payload.append(bytes)
        }
        header += "</ds3>"
        return Data("DUST3D 1.0 xml \(String(format: "%010d", 26 + header.utf8.count))\n\(header)".utf8) + payload
    }
}

private struct CancellingArchiveSourceBaker: ArchiveSourceBakingOperation {
    let output: SourceBakedMesh
    func load(data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions)
        async throws -> SourceBakedMesh
    {
        withUnsafeCurrentTask { $0?.cancel() }
        return output
    }
}

private struct FailingArchiveSourceBaker: ArchiveSourceBakingOperation {
    func load(data: Data, modelImages: [SourceMeshBakeImage], images: [MeshBakeImage], options: SourceMeshBakeOptions)
        async throws -> SourceBakedMesh
    {
        throw MeshLoadingError(status: 2, message: "original archive source failure")
    }
}
