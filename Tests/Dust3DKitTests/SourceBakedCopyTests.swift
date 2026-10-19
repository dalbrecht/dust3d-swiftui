import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

final class SourceBakedCopyTests: XCTestCase {
    func testKnownAndUnknownMappingsRemainIndependentOfPolicy() throws {
        var value = record()
        let unknown = try SourceBakedCopy.triangle(value, models: 0, components: 0)
        XCTAssertNil(unknown.packedUVs)
        XCTAssertNil(unknown.policy)
        XCTAssertNil(unknown.modelIndex)
        XCTAssertNil(unknown.componentIndex)
        value.uv_known = 1
        value.tangent.known = 1
        value.tangent.direction.0 = 1
        value.model_index = 0
        value.component_index = 0
        let known = try SourceBakedCopy.triangle(value, models: 1, components: 1)
        XCTAssertNotNil(known.packedUVs)
        XCTAssertNil(known.policy)
        XCTAssertEqual(known.modelIndex, 0)
        XCTAssertEqual(known.componentIndex, 0)
        value.policy_known = 1
        value.is_double_sided = 1
        value.alpha_cutoff = 0.25
        for (mode, expected) in [
            (DUST3D_IMPORTED_ALPHA_OPAQUE, ImportedAlphaMode.opaque),
            (DUST3D_IMPORTED_ALPHA_MASK, .mask), (DUST3D_IMPORTED_ALPHA_BLEND, .blend),
        ] {
            value.alpha_mode = mode
            let policy = try XCTUnwrap(SourceBakedCopy.triangle(value, models: 1, components: 1).policy)
            XCTAssertEqual(policy.alphaMode, expected)
            XCTAssertEqual(policy.alphaCutoff, 0.25)
            XCTAssertTrue(policy.isDoubleSided)
        }
    }

    func testRejectsInvalidForeignTriangleFlagsCoordinatesReferencesAndPolicy() throws {
        let changes: [(inout Dust3DSourceBakedTriangle) -> Void] = [
            { $0.uv_known = 2 }, { $0.policy_known = 2 }, { $0.is_double_sided = 2 },
            { $0.uv.0.0 = .nan }, { $0.uv.1.1 = .infinity }, { $0.uv.2.0 = -0.01 },
            {
                $0.uv_known = 1
                $0.uv.2.1 = 1.01
            }, { $0.uv.0.0 = 0.5 },
            { $0.model_index = 0 }, { $0.component_index = -2 },
            {
                $0.tangent.known = 1
                $0.tangent.direction.0 = 1
            },
            { $0.tangent.handedness = 0 },
            {
                $0.policy_known = 1
                $0.alpha_mode = Dust3DImportedAlphaMode(rawValue: 999)
            },
            {
                $0.policy_known = 1
                $0.alpha_cutoff = .nan
            },
            {
                $0.policy_known = 1
                $0.alpha_cutoff = -1
            },
            {
                $0.policy_known = 1
                $0.alpha_cutoff = 2
            },
        ]
        for change in changes {
            var value = record()
            change(&value)
            XCTAssertThrowsError(try SourceBakedCopy.triangle(value, models: 0, components: 0))
        }
    }

    func testRejectsCountsBeforeBorrowedViewsAreRead() throws {
        let nativeBytes = 3 * MemoryLayout<Dust3DVertex>.stride + MemoryLayout<Dust3DSourceBakedTriangle>.stride
        XCTAssertEqual(
            try SourceBakedCopy.validateCounts(
                vertices: 3, triangles: 1, models: 0, components: 0, payload: nativeBytes, maximum: nativeBytes), 0)
        for values in [
            (0, 0, 0, 0, nativeBytes), (4, 1, 0, 0, nativeBytes), (3, 2, 0, 0, nativeBytes),
            (3, 1, -1, 0, nativeBytes), (3, 1, 0, -1, nativeBytes), (3, 1, 0, 0, 0),
            (3, 1, 0, 0, nativeBytes + 1), (3, 1, Int.max, 0, nativeBytes),
            (3, 1, 0, Int.max, nativeBytes), (3, 1, 0, 0, nativeBytes - 1),
        ] {
            XCTAssertThrowsError(
                try SourceBakedCopy.validateCounts(
                    vertices: values.0, triangles: values.1, models: values.2, components: values.3, payload: values.4,
                    maximum: nativeBytes)
            ) {
                XCTAssertEqual($0 as? SourceMeshBakeError, .invalidNativeCounts)
            }
        }
    }

    func testQuotaChargesAvoidOverflowAndIdentityReadsAreBounded() throws {
        var budget = SourceBakeCopyBudget(maximum: 64)
        try budget.charge(2, width: 8)
        XCTAssertEqual(budget.used, 16)
        XCTAssertThrowsError(try budget.charge(Int.max, width: 8))
        XCTAssertThrowsError(try budget.charge(-1))
        XCTAssertThrowsError(try budget.charge(1, width: 0))
        XCTAssertThrowsError(try SourceBakedCopy.identity(nil, budget: &budget))
        try "model".withCString { pointer in
            XCTAssertEqual(try SourceBakedCopy.identity(pointer, budget: &budget).rawValue, "model")
        }
        try String(repeating: "a", count: 39).withCString { pointer in
            XCTAssertThrowsError(try SourceBakedCopy.identity(pointer, budget: &budget))
        }
        let invalid: [CChar] = [-1, 0]
        try invalid.withUnsafeBufferPointer { pointer in
            XCTAssertThrowsError(try SourceBakedCopy.identity(pointer.baseAddress, budget: &budget))
        }
    }

    func testPreservesFiniteSamplingClampAndRejectsImpossibleLevels() throws {
        let image = MeshTextureImage(width: 8, height: 4, rowStride: 32, pixels: Data(repeating: 0, count: 128))
        let maps = MeshTextureMaps(color: image, normal: nil, metallic: nil, roughness: nil, emissive: nil)
        XCTAssertEqual(try SourceBakedCopy.samplingLod(0, maps: maps), 0)
        XCTAssertEqual(try SourceBakedCopy.samplingLod(1.5, maps: maps), 1.5)
        XCTAssertEqual(try SourceBakedCopy.samplingLod(2, maps: maps), 2)
        for invalid in [Double.nan, .infinity, -1, 2.01] {
            XCTAssertThrowsError(try SourceBakedCopy.samplingLod(invalid, maps: maps))
        }
    }

    private func record() -> Dust3DSourceBakedTriangle {
        var value = Dust3DSourceBakedTriangle()
        value.model_index = -1
        value.component_index = -1
        value.tangent.handedness = 1
        return value
    }
}
