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
