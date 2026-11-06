import XCTest

@testable import Dust3DKit

@MainActor final class RigTemplateDisplayMeshTests: XCTestCase {
    private func fixture() -> RigTemplateMesh {
        RigTemplateMesh(
            vertices: [
                .init(position: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1), boneIndex: 0, role: .bone),
                .init(position: SIMD3(1, 0, 0), normal: SIMD3(0, 0, 1), boneIndex: 0, role: .selectedBone),
                .init(position: SIMD3(0, 1, 0), normal: SIMD3(0, 0, 1), boneIndex: 0, role: .ring),
            ], boneNames: ["Root"])
    }

    func testPureDisplayCopyPreservesTrianglesNormalsAndSemanticPalette() throws {
        let raw = fixture()
        let colors = [SIMD4<Float>(0, 1, 0, 1), SIMD4<Float>(1, 0, 0, 1), SIMD4<Float>(0, 0, 1, 1)]
        let mesh = try raw.displayMesh(boneColor: colors[0], selectedBoneColor: colors[1], ringColor: colors[2])
        XCTAssertEqual(mesh.triangleCount, 1)
        for index in raw.vertices.indices {
            XCTAssertEqual(mesh.vertices[index].position, raw.vertices[index].position)
            XCTAssertEqual(mesh.vertices[index].normal, raw.vertices[index].normal)
            XCTAssertEqual(mesh.vertices[index].color, colors[index])
        }
        XCTAssertEqual(raw.boneNames, ["Root"])
    }

    func testLaterPaletteCopiesAndInvalidColorsCannotChangeEarlierResult() throws {
        let raw = fixture()
        let first = try raw.displayMesh(boneColor: .one, selectedBoneColor: .one, ringColor: .one)
        let second = try raw.displayMesh(boneColor: .zero, selectedBoneColor: .zero, ringColor: .zero)
        XCTAssertTrue(first.vertices.allSatisfy { $0.color == .one })
        XCTAssertTrue(second.vertices.allSatisfy { $0.color == .zero })
        let invalid = SIMD4<Float>(.infinity, 0, 0, 1)
        for index in 0..<3 {
            var colors = [SIMD4<Float>.one, .one, .one]
            colors[index] = invalid
            XCTAssertThrowsError(
                try raw.displayMesh(boneColor: colors[0], selectedBoneColor: colors[1], ringColor: colors[2])
            ) {
                XCTAssertEqual($0 as? RigTemplateHierarchyError, .invalidMetadata("non-finite template display color"))
            }
        }
        XCTAssertTrue(first.vertices.allSatisfy { $0.color == .one })
    }

    func testCancelledDisplayCopyDoesNotPublishVertices() async {
        let raw = fixture()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try raw.displayMesh(boneColor: .one, selectedBoneColor: .one, ringColor: .one)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled display copy must not publish")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
