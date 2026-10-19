import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class ArchiveImportedMaterialTests: XCTestCase {
    private func resource(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func test_should_prepare_matching_owned_source_material_and_image_values() async throws {
        let data = try resource("ImportedSurface")
        let original = data
        let loaded = try await ArchiveImportedMaterialService().loadIfPresent(data: data, limits: .init())
        let value = try XCTUnwrap(loaded)
        XCTAssertEqual(data, original)
        XCTAssertEqual(value.surface.mesh.triangleCount, 4)
        XCTAssertEqual(value.materials.count, value.surface.modelIDs.count)
        let material = try XCTUnwrap(value.materials.first)
        XCTAssertEqual(try ImportedSurfaceIdentity(rawValue: material.definition.id), value.surface.modelIDs.first)
        XCTAssertEqual(material.definition.baseColor, SIMD4<Double>(0.25, 0.5, 0.75, 0.5))
        let image = try XCTUnwrap(material.image)
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.rowStride, 8)
        XCTAssertEqual(image.pixels.count, 16)
        XCTAssertEqual(value.decodedPayloadBytes, 16)
        XCTAssertTrue(value.surface.triangles.allSatisfy { $0.colorEncoding == .linear && $0.sourceUVs != nil })
    }

    func test_should_leave_procedural_archives_to_the_existing_baker() async throws {
        let value = try await ArchiveImportedMaterialService().loadIfPresent(data: resource("Capsule"), limits: .init())
        XCTAssertNil(value)
    }

    func test_should_bound_decode_storage_and_preserve_original_failures() async throws {
        let data = try resource("ImportedSurface")
        do {
            _ = try await ArchiveImportedMaterialService().loadIfPresent(
                data: data, limits: .init(maximumDecodedTotalBytes: 15))
            XCTFail("The 16-byte image must not fit the aggregate 15-byte limit")
        } catch {
            XCTAssertEqual(error as? MeshPNGDecodingError, .decodedLimitExceeded)
        }
        do {
            _ = try await ArchiveImportedMaterialService().loadIfPresent(data: Data("invalid".utf8), limits: .init())
            XCTFail("Invalid archives must retain the native cause")
        } catch {
            XCTAssertTrue(error is MeshLoadingError)
        }
        let exact = try await ArchiveImportedMaterialService().loadIfPresent(
            data: data, limits: .init(maximumDecodedTotalBytes: 16))
        XCTAssertEqual(exact?.decodedPayloadBytes, 16)
    }

    func test_should_join_by_exact_identity_and_bound_all_decoded_images() throws {
        let original = try XCTUnwrap(ImportedMaterialLoader.load(data: resource("ImportedSurface")).models.first)
        let other = reidentify(original, id: "{00000301-0000-4000-8000-000000000301}")
        let keys = try [other.id, original.id].map { try ImportedSurfaceIdentity(rawValue: $0) }
        let exact = try ImportedMaterialRenderLoader.decodeMaterials(
            [original, other], modelIDs: keys, limits: .init(maximumDecodedTotalBytes: 32))
        XCTAssertEqual(exact.bytes, 32)
        XCTAssertEqual(exact.materials.map(\.id), keys)
        XCTAssertThrowsError(
            try ImportedMaterialRenderLoader.decodeMaterials(
                [original, other], modelIDs: keys, limits: .init(maximumDecodedTotalBytes: 16))
        ) {
            XCTAssertEqual($0 as? ImportedMaterialRenderError, .decodedLimitExceeded(original.id))
        }
        XCTAssertThrowsError(
            try ImportedMaterialRenderLoader.decodeMaterials([original, original], modelIDs: keys, limits: .init())
        ) {
            XCTAssertEqual($0 as? ImportedMaterialRenderError, .duplicateMaterial(original.id))
        }
        XCTAssertThrowsError(
            try ImportedMaterialRenderLoader.decodeMaterials([original], modelIDs: keys, limits: .init())
        ) {
            XCTAssertEqual($0 as? ImportedMaterialRenderError, .missingMaterial(other.id))
        }
        let factorOnly = reidentify(original, id: other.id, hasImage: false)
        let solid = try ImportedMaterialRenderLoader.decodeMaterials([factorOnly], modelIDs: [keys[0]], limits: .init())
        XCTAssertEqual(solid.bytes, 0)
        XCTAssertNil(solid.materials.first?.image)
        XCTAssertEqual(solid.materials.first?.definition.baseColor, original.baseColor)
        for error in [
            ImportedMaterialRenderError.invalidLimits, .missingMaterial(other.id), .duplicateMaterial(other.id),
            .decodedLimitExceeded(other.id),
        ] {
            XCTAssertFalse(try XCTUnwrap(error.errorDescription).isEmpty)
        }
    }

    private func reidentify(_ value: ImportedModelMaterial, id: String, hasImage: Bool = true) -> ImportedModelMaterial
    {
        ImportedModelMaterial(
            id: id, baseColor: value.baseColor, metallic: value.metallic, roughness: value.roughness,
            emissive: value.emissive, alphaMode: value.alphaMode, alphaCutoff: value.alphaCutoff,
            isDoubleSided: value.isDoubleSided, sampler: hasImage ? value.sampler : nil,
            image: hasImage ? value.image : nil)
    }

    func test_should_validate_limits_before_native_work_and_cancel_before_publication() async throws {
        for limits in [
            ImportedMaterialRenderLimits(maximumDecodedTotalBytes: 0), .init(maximumDecodedTotalBytes: Int.max),
            .init(maximumEncodedImageBytes: 0),
        ] {
            do {
                _ = try await ArchiveImportedMaterialService().loadIfPresent(data: Data(), limits: limits)
                XCTFail("Invalid render limits must reject")
            } catch {
                XCTAssertEqual(error as? ImportedMaterialRenderError, .invalidLimits)
            }
        }
        let data = try resource("ImportedSurface")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ArchiveImportedMaterialService().loadIfPresent(data: data, limits: .init())
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled material preparation must not publish")
        } catch is CancellationError {}
    }
}
