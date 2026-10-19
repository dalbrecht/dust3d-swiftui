import Dust3DEngine
import Foundation
import XCTest
import simd

@testable import Dust3DKit

final class MeshLoaderTests: XCTestCase {
    func testExistingDocumentGeneratesFiniteColoredTriangles() throws {
        let mesh = try MeshLoader.load(data: fixture())
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertEqual(mesh.nodeCount, 3)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertTrue(mesh.warning.isEmpty)
        for vertex in mesh.vertices {
            XCTAssertTrue(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite)
            XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.001)
            XCTAssertGreaterThan(vertex.color.z, vertex.color.x)
        }
    }

    func testCopiedMeshSurvivesSubsequentLoads() throws {
        let first = try MeshLoader.load(data: fixture())
        let original = first.vertices[0].position
        _ = try MeshLoader.load(data: fixture())
        XCTAssertEqual(first.vertices[0].position, original)
    }

    func testRepositorySwordExampleGeneratesMultipleParts() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Sword", withExtension: "ds3", subdirectory: "Fixtures"))
        let mesh = try MeshLoader.load(data: Data(contentsOf: url))
        XCTAssertGreaterThan(mesh.partCount, 1)
        XCTAssertGreaterThan(mesh.nodeCount, 3)
        XCTAssertGreaterThan(mesh.triangleCount, 100)
    }

    func testRoundedCrossingGeneratesCompleteFiniteMesh() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "RoundedCrossing", withExtension: "ds3", subdirectory: "Fixtures"))
        let mesh = try MeshLoader.load(data: Data(contentsOf: url))
        XCTAssertEqual(mesh.nodeCount, 5)
        XCTAssertEqual(mesh.partCount, 2)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertTrue(mesh.warning.isEmpty)
        for vertex in mesh.vertices {
            XCTAssertTrue(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite)
            XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.001)
            XCTAssertTrue(vertex.color.x.isFinite && vertex.color.y.isFinite && vertex.color.z.isFinite)
        }
    }

    func testInvalidContainersReturnTypedErrors() throws {
        for data in [Data(), Data("not a document".utf8), Data(try fixture().prefix(60))] {
            XCTAssertThrowsError(try MeshLoader.load(data: data)) { error in
                XCTAssertTrue(error is MeshLoadingError)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testInvalidHeaderOffsetsAreRejectedWithoutAllocation() throws {
        for offset in ["0000000001", "9999999999", "-000000001", "xxxxxxxxxx"] {
            var data = try fixture()
            let lineEnd = try XCTUnwrap(data.firstIndex(of: 10))
            data.replaceSubrange((lineEnd - 11)..<(lineEnd - 1), with: offset.utf8)
            XCTAssertThrowsError(try MeshLoader.load(data: data))
        }
    }

    func testArchiveItemBoundsAndRequiredAttributesAreValidated() throws {
        for header in [
            "<model name=\"model.xml\" offset=\"18446744073709551615\" size=\"2\"/>",
            "<model name=\"model.xml\" offset=\"0\" size=\"999999\"/>",
            "<model name=\"model.xml\" size=\"10\"/>",
            "<model name=\"model.xml\" offset=\"0\" size=\"-1\"/>",
        ] {
            XCTAssertThrowsError(try MeshLoader.load(data: archive(xml: "<canvas/>", headerItems: header)))
        }
    }

    func testMalformedAndNonfiniteGeometryAreRejected() throws {
        XCTAssertThrowsError(try MeshLoader.load(data: archive(xml: "<canvas><nodes></canvas>")))
        let valid = try modelXML()
        XCTAssertThrowsError(
            try MeshLoader.load(
                data: archive(xml: valid.replacingOccurrences(of: "radius=\"0.12\"", with: "radius=\"nan\""))))
    }

    func testUnusedImportedMetadataRetainsProceduralGeometry() throws {
        let xml = try modelXML().replacingOccurrences(
            of: "visible=\"true\"", with: "visible=\"true\" importedModelId=\"{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}\"")
        let original = try MeshLoader.load(data: fixture())
        let mesh = try MeshLoader.load(data: archive(xml: xml))
        XCTAssertEqual(mesh.vertices.map(\.position), original.vertices.map(\.position))
        XCTAssertEqual(mesh.triangleCount, original.triangleCount)
    }

    func testRequiredMissingImportedGeometryFailsInsteadOfShowingPartialMesh() throws {
        let xml = try modelXML().replacingOccurrences(
            of: "visible=\"true\"",
            with: "visible=\"true\" target=\"ImportedModel\" importedModelId=\"{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}\""
        )
        XCTAssertThrowsError(try MeshLoader.load(data: archive(xml: xml))) { error in
            XCTAssertEqual((error as? MeshLoadingError)?.status, 1)
            XCTAssertTrue(error.localizedDescription.lowercased().contains("missing"))
        }
    }

    func testImageAssetsProduceAnUntexturedPreviewWarning() throws {
        let xml = try modelXML()
        let modelSize = xml.utf8.count
        let items =
            "<model name=\"model.xml\" offset=\"0\" size=\"\(modelSize)\"/><asset name=\"images/test.png\" offset=\"\(modelSize)\" size=\"0\"/>"
        let mesh = try MeshLoader.load(data: archive(xml: xml, headerItems: items))
        XCTAssertTrue(mesh.warning.contains("texture"))
    }

    func testNullHandleAccessorsAreSafe() {
        dust3d_mesh_destroy(nil)
        XCTAssertNil(dust3d_mesh_vertices(nil))
        XCTAssertEqual(dust3d_mesh_vertex_count(nil), 0)
        XCTAssertEqual(dust3d_mesh_node_count(nil), 0)
        XCTAssertEqual(dust3d_mesh_part_count(nil), 0)
        XCTAssertEqual(String(cString: dust3d_mesh_warning(nil)), "")
    }

    func testOversizedInputIsRejectedBeforeReadingTheBuffer() {
        var byte: UInt8 = 0
        var error = Dust3DError()
        let mesh = withUnsafePointer(to: &byte) { pointer in
            dust3d_mesh_load(pointer, MeshLoader.maximumFileSize + 1, &error)
        }
        XCTAssertNil(mesh)
        XCTAssertEqual(error.status, DUST3D_STATUS_LIMIT_EXCEEDED)
    }

    func testDuplicateComponentsAndExcessiveXmlDepthAreRejected() throws {
        let xml = try modelXML()
        let duplicate = xml.replacingOccurrences(
            of: "</components>", with: "<component id=\"{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}\"/></components>")
        XCTAssertThrowsError(try MeshLoader.load(data: archive(xml: duplicate)))
        let nested =
            "<canvas>" + String(repeating: "<component>", count: 129) + String(repeating: "</component>", count: 129)
            + "</canvas>"
        XCTAssertThrowsError(try MeshLoader.load(data: archive(xml: nested))) { error in
            XCTAssertEqual((error as? MeshLoadingError)?.status, 4)
        }
    }

    func testReversedLegacyEdgesStillGenerateTheSameBounds() throws {
        let original = try MeshLoader.load(data: fixture())
        let xml = try modelXML().replacingOccurrences(
            of: "from=\"{11111111-1111-4111-8111-111111111111}\" to=\"{22222222-2222-4222-8222-222222222222}\"",
            with: "from=\"{22222222-2222-4222-8222-222222222222}\" to=\"{11111111-1111-4111-8111-111111111111}\""
        )
        let reversed = try MeshLoader.load(data: archive(xml: xml))
        XCTAssertEqual(original.triangleCount, reversed.triangleCount)
        XCTAssertEqual(original.vertices.map(\.position), reversed.vertices.map(\.position))
    }

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func modelXML() throws -> String {
        let data = try fixture()
        let lineEnd = try XCTUnwrap(data.firstIndex(of: 10))
        let offset = try XCTUnwrap(Int(String(decoding: data[(lineEnd - 11)..<(lineEnd - 1)], as: UTF8.self)))
        return String(decoding: data[offset...], as: UTF8.self)
    }

    private func archive(xml: String, headerItems: String? = nil) -> Data {
        let items = headerItems ?? "<model name=\"model.xml\" offset=\"0\" size=\"\(xml.utf8.count)\"/>"
        let header = "<ds3>\(items)</ds3>\n"
        let prefix = "DUST3D 1.0 xml "
        let offset = prefix.utf8.count + 12 + header.utf8.count
        return Data((prefix + String(format: "%010d\r\n", offset) + header + xml).utf8)
    }
}
