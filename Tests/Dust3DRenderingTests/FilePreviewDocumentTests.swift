import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

final class FilePreviewDocumentTests: XCTestCase {
    func testShouldLoadExistingFileReadOnlyAndKeepMaterialFailureCause() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let before = try Data(contentsOf: fixture)
        let preview = try await FilePreviewDocumentService(materialBaker: MissingPreviewImage()).load(url: fixture)
        XCTAssertGreaterThan(try XCTUnwrap(preview.mesh).triangleCount, 0)
        XCTAssertNil(preview.bakedMesh)
        XCTAssertTrue(preview.materialError?.localizedDescription.contains("images/missing.png") == true)
        XCTAssertEqual(try Data(contentsOf: fixture), before)
    }

    func testTexturedFilePreviewNoticeTracksMaterialsAndPreservesLegacyLimits() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let original = try Dust3DDocument(data: Data(contentsOf: fixture))
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
            ))
        for legacy in [false, true] {
            var xml = try XCTUnwrap(String(data: original.modelXML, encoding: .utf8))
            if legacy { xml = xml.replacingOccurrences(of: "<component ", with: "<component wrapPattern='future' ") }
            let source = try Dust3DDocument(snapshotXML: Data(xml.utf8)).applying(
                .importComponentColorImage(
                    id: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", imageID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                    png: png))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ds3")
            try source.encoded().write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let preview = try await FilePreviewDocumentService().load(url: url)
            XCTAssertNotNil(preview.bakedMesh)
            XCTAssertEqual(preview.materialSourceCapabilities.hasLegacySurfaceDetails, legacy)
            XCTAssertEqual(
                preview.compatibilityWarning(), legacy ? "Procedural surface details are not yet displayed." : nil)
            XCTAssertEqual(preview.compatibilityWarning(materialRenderingFailed: true), preview.mesh?.warning)
            XCTAssertEqual(try Data(contentsOf: url), source.encoded())
            let failed = try await FilePreviewDocumentService(materialBaker: MissingPreviewImage()).load(url: url)
            XCTAssertEqual(failed.compatibilityWarning(), failed.mesh?.warning)
            XCTAssertTrue(failed.materialError?.localizedDescription.contains("images/missing.png") == true)
            XCTAssertEqual(try Data(contentsOf: url), source.encoded())
        }
    }

    func testShouldRejectEmbeddedLinksInsteadOfPresentingAnEmptyOrPartialModel() async throws {
        let xml = """
            <canvas><nodes/><edges/><parts/><components>
            <component id='{00000000-0000-4000-8000-000000000001}' linkDataType='glbId' linkData='retained-model'/>
            </components></canvas>
            """
        let archive = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ds3")
        try archive.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await FilePreviewDocumentService().load(url: url)
            XCTFail("Embedded content must not silently disappear")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Embedded"))
            XCTAssertEqual(try Data(contentsOf: url), archive)
        }
    }

    func testShouldRepresentEmptyDocumentsAndRejectOversizedFilesBeforeGeneration() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ds3")
        try Dust3DDocument.emptyArchive().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let empty = try await FilePreviewDocumentService().load(url: url)
        XCTAssertNil(empty.mesh)
        XCTAssertNil(empty.bakedMesh)
        XCTAssertNil(empty.materialError)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 64 * 1024 * 1024 + 1)
        try file.close()
        do {
            _ = try await FilePreviewDocumentService().load(url: url)
            XCTFail("Oversized preview input must fail before mesh generation")
        } catch let error as MeshLoadingError { XCTAssertEqual(error.status, 4) }
    }
}

private actor MissingPreviewImage: ArchiveTextureBaking {
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        throw ArchiveTextureBakingError.missingAsset("images/missing.png")
    }
}
