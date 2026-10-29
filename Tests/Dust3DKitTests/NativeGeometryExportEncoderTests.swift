import Foundation
import XCTest

@testable import Dust3DKit

private enum RoutingFailure: Error { case original }
private actor RoutingExportEncoder: DocumentExportEncoding {
    private(set) var archives: [Data] = []
    private(set) var formats: [DocumentExportFormat] = []
    private let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        archives.append(archive)
        formats.append(format)
        if fails { throw RoutingFailure.original }
        return .init(bytes: Data(format.rawValue.utf8), warning: "original " + format.rawValue)
    }
}

@MainActor
final class NativeGeometryExportEncoderTests: XCTestCase {
    func testRoutesExactCapturedSourceAndFormatWithoutCrossFormatFallback() async throws {
        let obj = RoutingExportEncoder()
        let fbx = RoutingExportEncoder()
        let router = NativeGeometryExportEncoder(obj: obj, fbx: fbx)
        let archive = Data([1, 2, 3])
        for format in [DocumentExportFormat.obj, .fbx] {
            let result = try await router.encode(archive: archive, format: format)
            XCTAssertEqual(result.bytes, Data(format.rawValue.utf8))
            XCTAssertEqual(result.warning, "original " + format.rawValue)
        }
        let objFormats = await obj.formats
        let fbxFormats = await fbx.formats
        let objArchives = await obj.archives
        let fbxArchives = await fbx.archives
        XCTAssertEqual(objFormats, [.obj])
        XCTAssertEqual(fbxFormats, [.fbx])
        XCTAssertEqual(objArchives, [archive])
        XCTAssertEqual(fbxArchives, [archive])
    }

    func testOriginalFBXFailureCannotFallBackToOBJ() async throws {
        let obj = RoutingExportEncoder()
        let fbx = RoutingExportEncoder(fails: true)
        let router = NativeGeometryExportEncoder(obj: obj, fbx: fbx)
        do {
            _ = try await router.encode(archive: Data([1]), format: .fbx)
            XCTFail("An export failure must not change formats")
        } catch RoutingFailure.original {}
        let objFormats = await obj.formats
        XCTAssertTrue(objFormats.isEmpty)
    }
}
