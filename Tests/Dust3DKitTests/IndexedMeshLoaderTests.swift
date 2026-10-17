import Dust3DDocument
import Foundation
import XCTest
import simd

@testable import Dust3DKit

final class IndexedMeshLoaderTests: XCTestCase {
    func testIndexedFixturesPreserveGeometryAndMetadata() throws {
        for name in ["Capsule", "Sword", "RoundedCrossing"] {
            let data = try fixture(name)
            let expanded = try MeshLoader.load(data: data)
            let indexed = try MeshLoader.loadIndexed(data: data)
            XCTAssertEqual(indexed.triangleCount, expanded.triangleCount)
            XCTAssertEqual(indexed.nodeCount, expanded.nodeCount)
            XCTAssertEqual(indexed.partCount, expanded.partCount)
            XCTAssertEqual(indexed.warning, expanded.warning)
            XCTAssertLessThanOrEqual(indexed.vertices.count, expanded.vertices.count)
            XCTAssertEqual(indexed.indices.count, expanded.vertices.count)
            XCTAssertTrue(indexed.indices.allSatisfy { Int($0) < indexed.vertices.count })
            for axis in 0..<3 {
                XCTAssertEqual(
                    try XCTUnwrap(indexed.vertices.map { $0.position[axis] }.min()),
                    try XCTUnwrap(expanded.vertices.map { $0.position[axis] }.min()), accuracy: 0.00001)
                XCTAssertEqual(
                    try XCTUnwrap(indexed.vertices.map { $0.position[axis] }.max()),
                    try XCTUnwrap(expanded.vertices.map { $0.position[axis] }.max()), accuracy: 0.00001)
            }
            for vertex in indexed.vertices {
                XCTAssertTrue((0..<3).allSatisfy { vertex.position[$0].isFinite })
                XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.001)
                XCTAssertTrue((0..<4).allSatisfy { vertex.color[$0].isFinite })
            }
        }
    }

    func testPayloadBudgetsPreserveTypedDiagnostics() throws {
        let data = try fixture("Capsule")
        for budget in [-1, Int.min, 1] {
            XCTAssertThrowsError(try MeshLoader.loadIndexed(data: data, maximumPayloadBytes: budget)) { error in
                let error = error as? MeshLoadingError
                XCTAssertEqual(error?.status, budget < 0 ? 1 : 4)
                XCTAssertFalse(error?.message.isEmpty ?? true)
            }
        }
        XCTAssertGreaterThan(try MeshLoader.loadIndexed(data: data, maximumPayloadBytes: 1_048_576).triangleCount, 0)
        XCTAssertThrowsError(try MeshLoader.loadIndexedIfPresent(data: data, maximumPayloadBytes: 1))
        XCTAssertThrowsError(try MeshLoader.loadIndexedIfPresent(data: Data())) { error in
            XCTAssertEqual((error as? MeshLoadingError)?.status, 1)
        }
    }

    func testCopiedIndexedBuffersSurviveSubsequentLoads() throws {
        let first = try MeshLoader.loadIndexed(data: fixture("Capsule"))
        let positions = first.vertices.map(\.position)
        let normals = first.vertices.map(\.normal)
        let colors = first.vertices.map(\.color)
        let indices = first.indices
        _ = try MeshLoader.loadIndexed(data: fixture("Sword"))
        _ = try MeshLoader.load(data: fixture("RoundedCrossing"))
        XCTAssertEqual(first.vertices.map(\.position), positions)
        XCTAssertEqual(first.vertices.map(\.normal), normals)
        XCTAssertEqual(first.vertices.map(\.color), colors)
        XCTAssertEqual(first.indices, indices)
        XCTAssertNotNil(try MeshLoader.loadIndexedIfPresent(data: fixture("Capsule")))
    }

    func testPlanarLoopPreservesKnownAttributesAndArea() throws {
        let mesh = try MeshLoader.loadIndexed(data: loopArchive())
        XCTAssertEqual(mesh.nodeCount, 4)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertEqual(mesh.vertices.count, 4)
        XCTAssertEqual(mesh.triangleCount, 2)
        XCTAssertFalse(mesh.warning.isEmpty)
        XCTAssertEqual(Set(mesh.indices), Set(0..<UInt32(mesh.vertices.count)))
        var area: Float = 0
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let positions = mesh.indices[offset..<(offset + 3)].map { mesh.vertices[Int($0)].position }
            area += simd_length(simd_cross(positions[1] - positions[0], positions[2] - positions[0])) / 2
        }
        XCTAssertEqual(area, 0.32, accuracy: 0.00001)
        for vertex in mesh.vertices {
            XCTAssertEqual(vertex.position.z, 0, accuracy: 0.00001)
            XCTAssertEqual(abs(vertex.normal.z), 1, accuracy: 0.00001)
            XCTAssertEqual(vertex.color.x, 0.2, accuracy: 0.00001)
            XCTAssertEqual(vertex.color.y, 0.4, accuracy: 0.00001)
            XCTAssertEqual(vertex.color.z, 0.8, accuracy: 0.00001)
            XCTAssertEqual(vertex.color.w, 1)
        }
    }

    func testSuccessfulEmptyIsDistinctFromPrecisionFailure() throws {
        let empty = try loopArchive(fill: false)
        XCTAssertNil(try MeshLoader.loadIndexedIfPresent(data: empty))
        XCTAssertThrowsError(try MeshLoader.loadIndexed(data: empty)) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 5)
        }
        let part = "{00000100-0000-4000-8000-000000000100}"
        let xml =
            "<canvas originX='0' originY='0' originZ='0'><nodes><node id='{00001000-0000-4000-8000-000000001000}' partId='\(part)' x='1000000' y='1000000' z='1000000' radius='.001'/></nodes><edges/><parts><part id='\(part)'/></parts><components><component id='{00000200-0000-4000-8000-000000000200}' linkDataType='partId' linkData='\(part)'/></components></canvas>"
        let far = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        XCTAssertThrowsError(try MeshLoader.loadIndexedIfPresent(data: far)) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 3)
            XCTAssertTrue(($0 as? MeshLoadingError)?.message.contains("precision") == true)
        }
    }

    @MainActor
    func testConcurrentLoadsReturnIndependentSendableValues() async throws {
        let data = try loopArchive()
        let meshes = try await withThrowingTaskGroup(of: IndexedMesh.self) { group in
            for _ in 0..<4 { group.addTask { try MeshLoader.loadIndexed(data: data) } }
            var results: [IndexedMesh] = []
            for try await mesh in group { results.append(mesh) }
            return results
        }
        XCTAssertEqual(meshes.count, 4)
        for mesh in meshes {
            XCTAssertEqual(mesh.vertices.count, 4)
            XCTAssertEqual(mesh.indices.count, 6)
            XCTAssertTrue(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
        }
    }

    private func loopArchive(fill: Bool = true) throws -> Data {
        // Independent synthetic diamond, with known area and uniform attributes.
        let part = "{00000100-0000-4000-8000-000000000100}"
        let nodes = (0..<4).map { "{0000100\($0)-0000-4000-8000-00000000100\($0)}" }
        let positions = [(0.9, 0.5), (0.5, 0.9), (0.1, 0.5), (0.5, 0.1)]
        var xml = "<canvas originX='.5' originY='.5' originZ='.5'><nodes>"
        for index in 0..<4 {
            xml +=
                "<node id='\(nodes[index])' partId='\(part)' x='\(positions[index].0)' y='\(positions[index].1)' z='.5' radius='.05'/>"
        }
        xml += "</nodes><edges>"
        for index in 0..<4 {
            xml +=
                "<edge id='{0000200\(index)-0000-4000-8000-00000000200\(index)}' partId='\(part)' from='\(nodes[index])' to='\(nodes[(index + 1) % 4])'/>"
        }
        xml +=
            "</edges><parts><part id='\(part)' target='StitchingLoop' fillLoopInterior='\(fill)'/></parts><components><component id='{00000300-0000-4000-8000-000000000300}' color='#3366cc' wrapPattern='Spots'><component id='{00000200-0000-4000-8000-000000000200}' linkDataType='partId' linkData='\(part)'/></component></components></canvas>"
        return try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
