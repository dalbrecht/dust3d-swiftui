import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class ImportedMaterialLoaderTests: XCTestCase {
    private let modelA = "{00000300-0000-4000-8000-000000000300}"
    private let modelB = "{ABCDEFAB-0000-4000-8000-000000000301}"

    private func resource(_ name: String, _ extensionName: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: extensionName, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func test_should_copy_material_fields_bindings_and_encoded_images() throws {
        let data = try resource("ImportedMaterials", "ds3")
        let original = data
        let result = try ImportedMaterialLoader.load(data: data)
        XCTAssertEqual(data, original)
        XCTAssertEqual(result.models.count, 2)
        XCTAssertEqual(result.bindings.count, 4)
        let png = try XCTUnwrap(result.models.first { $0.id == modelA })
        XCTAssertEqual(png.baseColor, SIMD4<Double>(0.25, 0.5, 0.75, 0.5))
        XCTAssertEqual(png.metallic, 0.125)
        XCTAssertEqual(png.roughness, 0.625)
        XCTAssertEqual(png.emissive, SIMD3<Double>(0.1, 0.2, 0.3))
        XCTAssertEqual(png.alphaMode, .mask)
        XCTAssertEqual(png.alphaCutoff, 0.375)
        XCTAssertTrue(png.isDoubleSided)
        XCTAssertEqual(png.sampler?.magnification, .nearest)
        XCTAssertEqual(png.sampler?.minification, .nearestMipmapNearest)
        XCTAssertEqual(png.sampler?.wrapS, .clampToEdge)
        XCTAssertEqual(png.sampler?.wrapT, .mirroredRepeat)
        XCTAssertEqual(png.image?.encoding, .png)
        XCTAssertEqual(png.image?.bytes, try resource("ImportedMaterial", "png"))
        let jpeg = try XCTUnwrap(result.models.first { $0.id == modelB })
        XCTAssertEqual(jpeg.baseColor, SIMD4<Double>(repeating: 1))
        XCTAssertEqual(jpeg.metallic, 1)
        XCTAssertEqual(jpeg.roughness, 1)
        XCTAssertEqual(jpeg.emissive, .zero)
        XCTAssertEqual(jpeg.alphaMode, .opaque)
        XCTAssertEqual(jpeg.alphaCutoff, 0.5)
        XCTAssertFalse(jpeg.isDoubleSided)
        XCTAssertNil(jpeg.sampler?.magnification)
        XCTAssertNil(jpeg.sampler?.minification)
        XCTAssertEqual(jpeg.sampler?.wrapS, .repeatTexture)
        XCTAssertEqual(jpeg.sampler?.wrapT, .repeatTexture)
        XCTAssertEqual(jpeg.image?.encoding, .jpeg)
        XCTAssertEqual(jpeg.image?.bytes, try resource("ImportedMaterial", "jpg"))
        let firstPart = "{00000100-0000-4000-8000-000000000100}"
        let firstComponent = "{00000200-0000-4000-8000-000000000200}"
        XCTAssertTrue(
            result.bindings.contains {
                $0.partID == firstPart && $0.componentID == firstComponent && $0.modelID == modelA
            })
        XCTAssertTrue(
            result.bindings.contains {
                $0.partID == String(firstPart.dropFirst().dropLast())
                    && $0.componentID == String(firstComponent.dropFirst().dropLast())
            })
        XCTAssertTrue(result.bindings.contains { $0.componentID == nil && $0.modelID == modelB })
    }

    func test_should_keep_copies_after_input_and_subsequent_owner_teardown() throws {
        var input = try resource("ImportedMaterials", "ds3")
        let original = input
        let first = try ImportedMaterialLoader.load(data: input)
        input.resetBytes(in: 0..<input.count)
        _ = try ImportedMaterialLoader.load(data: original)
        XCTAssertEqual(first.models.first { $0.id == modelA }?.image?.bytes, try resource("ImportedMaterial", "png"))
        let exact = try ImportedMaterialLoader.load(
            data: original, options: .init(maximumCopiedPayloadBytes: first.copiedPayloadBytes))
        XCTAssertEqual(exact, first)
        XCTAssertThrowsError(
            try ImportedMaterialLoader.load(
                data: original, options: .init(maximumCopiedPayloadBytes: first.copiedPayloadBytes - 1))
        ) {
            XCTAssertEqual($0 as? ImportedMaterialError, .copyLimitExceeded)
        }
    }

    func test_should_preserve_import_assets_through_edit_undo_redo_and_reopen() throws {
        let data = try resource("ImportedPreview", "ds3")
        let original = try Dust3DDocument(data: data)
        var history = DocumentHistory(document: original)
        let nodeID = "{00001000-0000-4000-8000-000000001000}"
        let node = try original.node(id: nodeID)
        try history.apply(.setNode(id: nodeID, position: node.position, radius: 0.2))
        let edited = history.document.encoded()
        let reopened = try Dust3DDocument(data: edited)
        XCTAssertEqual(reopened.asset(named: "models/\(modelA).glb"), original.asset(named: "models/\(modelA).glb"))
        XCTAssertEqual(try ImportedMaterialLoader.load(data: edited).models.count, 1)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), data)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited)
        let mesh = try MeshLoader.load(data: edited)
        XCTAssertEqual(mesh.triangleCount, 4)
        XCTAssertTrue(mesh.warning.contains("Imported geometry preview"))
        XCTAssertTrue(mesh.warning.contains("not yet applied"))
    }

    func test_should_allow_empty_and_procedural_material_sets_with_original_native_errors() throws {
        XCTAssertTrue(try ImportedMaterialLoader.load(data: Dust3DDocument.emptyArchive()).models.isEmpty)
        XCTAssertTrue(try ImportedMaterialLoader.load(data: resource("Capsule", "ds3")).models.isEmpty)
        XCTAssertThrowsError(try ImportedMaterialLoader.load(data: Data("invalid".utf8))) {
            XCTAssertTrue($0 is MeshLoadingError)
            XCTAssertFalse($0.localizedDescription.isEmpty)
        }
        for options in [
            ImportedMaterialOptions(maximumNativePayloadBytes: -1),
            .init(maximumNativePayloadBytes: 256 * 1024 * 1024 + 1),
            .init(maximumCopiedPayloadBytes: 0),
            .init(maximumCopiedPayloadBytes: -1),
        ] {
            XCTAssertThrowsError(try ImportedMaterialLoader.load(data: Data(), options: options)) {
                XCTAssertEqual($0 as? ImportedMaterialError, .invalidLimits)
            }
        }
    }

    func test_should_load_immutable_materials_through_background_actor() async throws {
        let data = try resource("ImportedMaterials", "ds3")
        let value = try await ImportedMaterialService().load(data: data)
        XCTAssertEqual(value.models.count, 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ImportedMaterialService().load(data: data)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled inspection should not publish copied materials")
        } catch is CancellationError {
        }
    }
    func test_should_inspect_real_baseline_progressive_and_grayscale_jpeg_fixtures() throws {
        for name in ["ImportedMaterial", "ImportedProgressive", "ImportedGray"] {
            let metadata = try JPEGContainerMetadata(data: resource(name, "jpg"))
            XCTAssertEqual(metadata.width, 2)
            XCTAssertEqual(metadata.height, 2)
            XCTAssertEqual(metadata.isProgressive, name == "ImportedProgressive")
            XCTAssertEqual(metadata.componentCount, name == "ImportedGray" ? 1 : 3)
        }
    }

    func test_should_preserve_original_background_operation_error() async {
        let service = ImportedMaterialService(operation: FailingMaterialOperation())
        do {
            _ = try await service.load(data: Data())
            XCTFail("Expected the original operation error")
        } catch {
            XCTAssertEqual(error as? MaterialOperationFailure, .originalCause)
        }
    }

    func test_should_discard_materials_when_cancelled_during_operation() async {
        let service = ImportedMaterialService(operation: CancellingMaterialOperation())
        do {
            _ = try await Task { try await service.load(data: Data()) }.value
            XCTFail("Cancellation during native work must prevent publication")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

}

private enum MaterialOperationFailure: Error, Equatable {
    case originalCause
}

private struct FailingMaterialOperation: ImportedMaterialOperation {
    func load(data: Data, options: ImportedMaterialOptions) throws -> ImportedMaterials {
        throw MaterialOperationFailure.originalCause
    }
}

private struct CancellingMaterialOperation: ImportedMaterialOperation {
    func load(data: Data, options: ImportedMaterialOptions) throws -> ImportedMaterials {
        withUnsafeCurrentTask { $0?.cancel() }
        return ImportedMaterials(models: [], bindings: [], nativePayloadBytes: 0, copiedPayloadBytes: 0)
    }
}
