import Metal
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class ImportedFilePreviewTests: XCTestCase {
    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/ImportedSurface.ds3")
    }

    func test_should_prepare_imported_file_read_only_and_remove_only_presented_material_notice() async throws {
        let url = fixture()
        let before = try Data(contentsOf: url)
        let document = try await FilePreviewDocumentService().load(url: url)
        XCTAssertEqual(document.mesh?.triangleCount, 4)
        XCTAssertNotNil(document.importedMaterials)
        XCTAssertNil(document.bakedMesh)
        XCTAssertNil(document.materialError)
        XCTAssertNotNil(document.compatibilityWarning())
        XCTAssertNil(document.compatibilityWarning(materialsRendered: true))
        XCTAssertEqual(
            document.compatibilityWarning(materialsRendered: true, materialRenderingFailed: true),
            document.mesh?.warning)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func test_should_keep_ordinary_geometry_and_original_imported_preparation_cause() async throws {
        let loader = FilePreviewDocumentService(
            importedMaterialLoader: FailingPreviewImporter(error: ImportedSurfaceError.copyLimitExceeded))
        let before = try Data(contentsOf: fixture())
        let document = try await loader.load(url: fixture())
        XCTAssertEqual(document.mesh?.triangleCount, 4)
        XCTAssertNil(document.importedMaterials)
        XCTAssertNil(document.bakedMesh)
        XCTAssertEqual(document.materialError as? ImportedSurfaceError, .copyLimitExceeded)
        XCTAssertEqual(document.compatibilityWarning(materialsRendered: true), document.mesh?.warning)
        XCTAssertEqual(try Data(contentsOf: fixture()), before)
    }

    func test_should_propagate_imported_cancellation_instead_of_reporting_geometry_success() async throws {
        let loader = FilePreviewDocumentService(
            importedMaterialLoader: FailingPreviewImporter(error: CancellationError()))
        do {
            _ = try await loader.load(url: fixture())
            XCTFail("Cancellation must not publish a partial preview")
        } catch is CancellationError {}
    }

    func test_should_render_imported_alpha_through_production_readback_and_premultiplication() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device is available") }
        let data = try ImportedMetalFixture.quad(mode: .blend, layers: [.init(rgba: [255, 0, 0, 128])])
        let image = try await FilePreviewRenderer.render(
            importedMaterials: data, maximumSize: CGSize(width: 13, height: 7), scale: 1)
        XCTAssertEqual(image.width, 13)
        XCTAssertEqual(image.height, 7)
        XCTAssertEqual(image.rowStride, 52)
        XCTAssertEqual(image.pixels.count, 364)
        XCTAssertEqual(image.pixels[3], 0)
        let center = (3 * 13 + 6) * 4
        XCTAssertEqual(image.pixels[center + 3], 128)
        XCTAssertGreaterThan(image.pixels[center + 2], image.pixels[center])
        XCTAssertLessThanOrEqual(image.pixels[center + 2], 128)
        XCTAssertEqual(try image.makeCGImage().width, 13)
        let real = try XCTUnwrap(ImportedMaterialRenderLoader.loadIfPresent(data: Data(contentsOf: fixture())))
        let actual = try await FilePreviewRenderer.render(
            importedMaterials: real, maximumSize: CGSize(width: 64, height: 64), scale: 1)
        XCTAssertTrue(stride(from: 3, to: actual.pixels.count, by: 4).contains { actual.pixels[$0] > 0 })
    }

    func test_should_reject_invalid_and_cancelled_imported_render_requests() async throws {
        let data = try ImportedMetalFixture.quad()
        do {
            _ = try await FilePreviewRenderer.render(importedMaterials: data, maximumSize: .zero, scale: 1)
            XCTFail("Invalid dimensions must fail")
        } catch { XCTAssertEqual(error as? FilePreviewError, .invalidDimensions) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FilePreviewRenderer.render(
                importedMaterials: data, maximumSize: CGSize(width: 64, height: 64), scale: 1)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled rendering must not publish an image")
        } catch is CancellationError {}
    }
}

private struct FailingPreviewImporter: ArchiveImportedMaterialLoading {
    let error: any Error
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        throw error
    }
}
