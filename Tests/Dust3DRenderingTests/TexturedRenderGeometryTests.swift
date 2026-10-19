import Dust3DDocument
import Foundation
import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

final class TexturedRenderGeometryTests: XCTestCase {
    func testShouldShareOnlyCompleteMatchingCornersInStableTriangleOrder() throws {
        let source = try fixture()
        let result = try TexturedRenderGeometry(bakedMesh: source)
        XCTAssertEqual(result.indices, [0, 1, 2, 0, 1, 2])
        XCTAssertEqual(result.vertices.count, 3)
        XCTAssertEqual(result.metadata, .legacy(source.metadata))
        XCTAssertEqual(result.textures.color, source.textures.color)
        XCTAssertEqual(result.vertices[0].textureCoordinate, SIMD4(0, 0, 1, 1))
        XCTAssertEqual(result.vertices[0].tangent, SIMD4(1, 0, 0, 1))
        XCTAssertEqual(result.vertices[0].color, source.geometry.vertices[0].color)
        XCTAssertTrue(
            result.vertices.allSatisfy { simd_length(SIMD3($0.position.x, $0.position.y, $0.position.z)) <= 1.00001 })
    }

    func testShouldKeepUVTangentMaterialAndMappingSeamsDistinct() throws {
        let changedUV = MeshUvCorners(first: SIMD2(0.25, 0), second: SIMD2(1, 0), third: SIMD2(0, 1))
        let cases: [(MeshWithBakedTextures, Int)] = [
            (try fixture(secondCorners: changedUV), 4),
            (
                try fixture(
                    secondTangent: MeshTextureTangent(direction: SIMD3(0, 1, 0), handedness: 1, hasMapping: true)), 6
            ),
            (
                try fixture(
                    secondTangent: MeshTextureTangent(direction: SIMD3(1, 0, 0), handedness: -1, hasMapping: true)), 6
            ),
            (try fixture(secondComponent: 1), 6),
            (try fixture(secondKind: 99), 6),
            (try fixture(secondComponent: -1, secondKind: 0), 6),
            (try fixture(secondComponent: -1, secondKind: 2), 6),
            (try fixture(secondComponent: -1, secondKind: 99), 6),
            (
                try fixture(
                    secondTangent: MeshTextureTangent(direction: SIMD3(1, 0, 0), handedness: 1, hasMapping: false)), 6
            ),
            (try fixture(secondMapped: false, zeroUVs: true), 6),
        ]
        for (source, count) in cases {
            let result = try TexturedRenderGeometry(bakedMesh: source)
            XCTAssertEqual(result.vertices.count, count)
            XCTAssertEqual(result.indices.count, 6)
            XCTAssertEqual(result.metadata, .legacy(source.metadata))
        }
    }

    func testShouldRetainPositionNormalColorAndSubFloatUVSeams() throws {
        let source = try fixture()
        let original = source.geometry.vertices[3]
        let changed = [
            MeshVertex(position: SIMD3(0.25, 0, 0), normal: original.normal, color: original.color),
            MeshVertex(position: original.position, normal: SIMD3(0, 1, 0), color: original.color),
            MeshVertex(position: original.position, normal: original.normal, color: SIMD4(0, 1, 0, 1)),
        ]
        for vertex in changed {
            var vertices = source.geometry.vertices
            vertices[3] = vertex
            let mesh = replacing(source, vertices: vertices)
            XCTAssertEqual(try TexturedRenderGeometry(bakedMesh: mesh).vertices.count, 4)
        }
        let tinyUV = MeshUvCorners(
            first: SIMD2(Double.leastNonzeroMagnitude, 0), second: SIMD2(1, 0), third: SIMD2(0, 1))
        let prepared = try TexturedRenderGeometry(bakedMesh: fixture(secondCorners: tinyUV))
        XCTAssertEqual(prepared.vertices.count, 4)
        XCTAssertEqual(prepared.vertices[0].textureCoordinate, prepared.vertices[3].textureCoordinate)
        XCTAssertNotEqual(prepared.indices[0], prepared.indices[3])
    }

    func testShouldRejectNonfiniteVerticesAndInvalidTangentFrames() throws {
        let source = try fixture()
        let original = source.geometry.vertices[0]
        for invalid in [
            MeshVertex(position: SIMD3(.nan, 0, 0), normal: original.normal, color: original.color),
            MeshVertex(position: original.position, normal: SIMD3(.infinity, 0, 0), color: original.color),
            MeshVertex(position: original.position, normal: original.normal, color: SIMD4(1, 1, .nan, 1)),
        ] {
            var vertices = source.geometry.vertices
            vertices[0] = invalid
            XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: replacing(source, vertices: vertices)))
        }
        for invalid in [
            MeshTextureTangent(direction: SIMD3(.nan, 0, 0), handedness: 1, hasMapping: true),
            MeshTextureTangent(direction: SIMD3(2, 0, 0), handedness: 1, hasMapping: true),
            MeshTextureTangent(direction: SIMD3(1, 0, 0), handedness: 0, hasMapping: true),
        ] {
            XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: fixture(secondTangent: invalid))) {
                XCTAssertEqual($0 as? TexturedRenderGeometryError, .invalidTangent)
            }
        }
        let invalid = try fixture(
            secondTangent: MeshTextureTangent(direction: SIMD3(1, 0, 0), handedness: 1, hasMapping: true),
            secondMapped: false, zeroUVs: true)
        XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: invalid))
        XCTAssertThrowsError(
            try TexturedRenderGeometry(
                bakedMesh: replacing(source, vertices: Array(source.geometry.vertices.prefix(3)))))
    }

    func testShouldBoundIndexDominatedBuffersAndObserveCancellation() async throws {
        let source = try fixture(repetitions: 100)
        let prepared = try TexturedRenderGeometry(bakedMesh: source)
        let indexBytes = prepared.indices.count * MemoryLayout<UInt32>.stride
        XCTAssertGreaterThan(indexBytes, prepared.vertices.count * MemoryLayout<TexturedRenderGeometry.Vertex>.stride)
        XCTAssertNoThrow(try prepared.validateBufferLengths(maximumBufferLength: indexBytes))
        XCTAssertThrowsError(try prepared.validateBufferLengths(maximumBufferLength: indexBytes - 1))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TexturedRenderGeometry(bakedMesh: source)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private func replacing(_ source: MeshWithBakedTextures, vertices: [MeshVertex]) -> MeshWithBakedTextures {
        MeshWithBakedTextures(
            geometry: Mesh(vertices: vertices, nodeCount: 1, partCount: 1, warning: ""),
            metadata: source.metadata, tangents: source.tangents, textures: source.textures)
    }

    func testShouldRejectInvalidPayloadsAndHonorExactLogicalAndDeviceLimits() throws {
        let source = try fixture()
        let expectedBytes = 3 * MemoryLayout<TexturedRenderGeometry.Vertex>.stride + 6 * MemoryLayout<UInt32>.stride
        let result = try TexturedRenderGeometry(bakedMesh: source, maximumPayloadBytes: expectedBytes)
        for limit in [-1, 0, 1, expectedBytes - 1, Int.max] {
            XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: source, maximumPayloadBytes: limit))
        }
        let vertexBytes = result.vertices.count * MemoryLayout<TexturedRenderGeometry.Vertex>.stride
        XCTAssertNoThrow(try result.validateBufferLengths(maximumBufferLength: vertexBytes))
        for limit in [-1, 0, vertexBytes - 1] {
            XCTAssertThrowsError(try result.validateBufferLengths(maximumBufferLength: limit))
        }
        let invalidGeometry = Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: "")
        let invalid = MeshWithBakedTextures(
            geometry: invalidGeometry, metadata: source.metadata, tangents: source.tangents, textures: source.textures)
        XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: invalid))
        let missingTangents = MeshWithBakedTextures(
            geometry: source.geometry, metadata: source.metadata, tangents: [], textures: source.textures)
        XCTAssertThrowsError(try TexturedRenderGeometry(bakedMesh: missingTangents))
    }

    func testShouldPreserveActualBakerTriangleAttributes() throws {
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let xml =
            "<canvas originX='0' originY='0' originZ='0'><nodes><node id='{11111111-1111-4111-8111-111111111111}' partId='\(part)' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='\(part)'/></parts><components><component id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId' linkData='\(part)' color='#ff8000'/></components></canvas>"
        let source = try MeshLoader.loadBaked(
            data: Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded(),
            options: MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8))
        let result = try TexturedRenderGeometry(bakedMesh: source)
        XCTAssertEqual(result.indices.count, source.geometry.vertices.count)
        XCTAssertEqual(result.metadata, .legacy(source.metadata))
        let ordinary = try RenderGeometry(mesh: .expanded(source.geometry))
        for (corner, index) in result.indices.enumerated() {
            let vertex = result.vertices[Int(index)]
            let triangle = source.metadata.triangles[corner / 3]
            let uv = [triangle.corners.first, triangle.corners.second, triangle.corners.third][corner % 3]
            XCTAssertEqual(vertex.textureCoordinate.x, Float(uv.x))
            XCTAssertEqual(vertex.textureCoordinate.y, Float(uv.y))
            XCTAssertEqual(vertex.color, source.geometry.vertices[corner].color)
            XCTAssertEqual(vertex.position, ordinary.vertices[corner].position)
            XCTAssertEqual(vertex.normal, SIMD4(source.geometry.vertices[corner].normal, 0))
            let tangent = source.tangents[corner / 3]
            XCTAssertEqual(vertex.tangent, SIMD4(tangent.direction, tangent.handedness))
            XCTAssertEqual(vertex.textureCoordinate.z, triangle.hasMapping ? 1 : 0)
            XCTAssertEqual(vertex.textureCoordinate.w, tangent.hasMapping ? 1 : 0)
        }
    }

    private func fixture(
        secondCorners: MeshUvCorners? = nil, secondTangent: MeshTextureTangent? = nil,
        secondComponent: Int = 0, secondKind: UInt32 = 1, secondMapped: Bool = true, zeroUVs: Bool = false,
        repetitions: Int = 1
    ) throws -> MeshWithBakedTextures {
        let corners =
            zeroUVs
            ? MeshUvCorners(first: .zero, second: .zero, third: .zero)
            : MeshUvCorners(first: .zero, second: SIMD2(1, 0), third: SIMD2(0, 1))
        let metadata = try MeshUvMetadata(
            componentIDs: ["{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"],
            triangles: Array(
                repeating: [
                    RawMeshUvTriangle(corners: corners, known: 1, componentKind: 1, componentIndex: 0),
                    RawMeshUvTriangle(
                        corners: secondCorners ?? corners, known: secondMapped ? 1 : 0, componentKind: secondKind,
                        componentIndex: secondComponent),
                ], count: repetitions
            ).flatMap { $0 },
            charts: [
                RawMeshUvChart(
                    origin: .zero, size: SIMD2(1, 1), color: SIMD4(1, 1, 1, 1), flipped: 0, componentKind: 1,
                    componentIndex: 0, imageID: nil)
            ],
            gradients: [], expandedVertexCount: 6 * repetitions, packedTextureSize: 8)
        let vertices = [SIMD3<Float>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)].map {
            MeshVertex(position: $0, normal: SIMD3(0, 0, 1), color: SIMD4(1, 0.5, 0, 1))
        }
        let tangent = MeshTextureTangent(direction: SIMD3(1, 0, 0), handedness: 1, hasMapping: !zeroUVs)
        let image = MeshTextureImage(width: 1, height: 1, rowStride: 4, pixels: Data([255, 128, 0, 255]))
        return MeshWithBakedTextures(
            geometry: Mesh(
                vertices: Array(repeating: vertices + vertices, count: repetitions).flatMap { $0 }, nodeCount: 1,
                partCount: 1, warning: ""), metadata: metadata,
            tangents: Array(repeating: [tangent, secondTangent ?? tangent], count: repetitions).flatMap { $0 },
            textures: MeshTextureMaps(color: image, normal: nil, metallic: nil, roughness: nil, emissive: nil))
    }
}
