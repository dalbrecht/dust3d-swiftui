import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

final class ImportedSurfaceCopyTests: XCTestCase {
    private func unknown() -> Dust3DImportedSurfaceTriangle {
        var value = Dust3DImportedSurfaceTriangle()
        value.model_index = -1
        value.component_index = -1
        return value
    }

    func test_should_preserve_unknown_and_authored_repeat_coordinates() throws {
        let unknown = try ImportedSurfaceCopy.triangle(unknown(), models: 0, components: 0)
        XCTAssertNil(unknown.sourceUVs)
        XCTAssertNil(unknown.modelIndex)
        XCTAssertNil(unknown.componentIndex)
        XCTAssertEqual(unknown.colorEncoding, .sRGB)
        var repeated = self.unknown()
        repeated.model_index = 0
        repeated.component_index = 1
        repeated.uv_known = 1
        repeated.uv.0 = (-2, 3)
        repeated.color_encoding = DUST3D_SURFACE_COLOR_LINEAR
        let copied = try ImportedSurfaceCopy.triangle(repeated, models: 1, components: 2)
        XCTAssertEqual(copied.sourceUVs?.first, SIMD2(-2, 3))
        XCTAssertEqual(copied.componentIndex, 1)
        XCTAssertEqual(copied.colorEncoding, .linear)
        repeated.uv_known = 0
        repeated.uv.0 = (0, 0)
        XCTAssertNil(try ImportedSurfaceCopy.triangle(repeated, models: 1, components: 2).sourceUVs)
    }

    func test_should_reject_invalid_source_flags_indices_coordinates_and_colors() {
        let mutations: [(inout Dust3DImportedSurfaceTriangle) -> Void] = [
            { $0.uv_known = 2 }, { $0.model_index = 1 }, { $0.component_index = -2 },
            { $0.component_index = 1 }, { $0.uv_known = 1 },
            { $0.uv.0.0 = .nan }, { $0.uv.1.1 = .infinity }, { $0.uv.2.0 = 1 },
            { $0.color.0.0 = -.infinity }, { $0.color.1.2 = -0.1 }, { $0.color.2.3 = 1.01 },
            { $0.color_encoding = Dust3DSurfaceColorEncoding(rawValue: 99) },
        ]
        for mutate in mutations {
            var value = unknown()
            mutate(&value)
            XCTAssertThrowsError(try ImportedSurfaceCopy.triangle(value, models: 1, components: 1)) {
                XCTAssertEqual($0 as? ImportedSurfaceError, .invalidTriangle)
            }
        }
    }

    func test_should_reject_native_counts_before_buffer_allocation() throws {
        let payload = 4096
        try ImportedSurfaceCopy.validateCounts(
            triangles: 1, vertices: 3, models: 1, components: 1, payload: payload, maximum: payload)
        for (triangles, vertices, models, components, bytes, maximum) in [
            (1, 0, 0, 0, payload, payload), (1, 4, 0, 0, payload, payload),
            (2, 3, 0, 0, payload, payload), (1, 3, -1, 0, payload, payload),
            (1, 3, 0, -1, payload, payload), (1, 3, 0, 0, 0, payload),
            (1, 3, 0, 0, payload, payload - 1), (1, 3, 0, 0, 1, payload),
            (1, 3, Int.max, 0, payload, payload), (1, 3, 0, Int.max, payload, payload),
        ] {
            XCTAssertThrowsError(
                try ImportedSurfaceCopy.validateCounts(
                    triangles: triangles, vertices: vertices, models: models, components: components, payload: bytes,
                    maximum: maximum)
            ) {
                XCTAssertEqual($0 as? ImportedSurfaceError, .invalidNativeCounts)
            }
        }
    }

    func test_should_bound_identity_reads_and_checked_copy_arithmetic() throws {
        var budget = ImportedSurfaceCopyBudget(maximum: 5)
        let value = try "abcd".withCString { try ImportedSurfaceCopy.identity($0, budget: &budget) }
        XCTAssertEqual(value, "abcd")
        XCTAssertEqual(budget.used, 5)
        XCTAssertThrowsError(try budget.charge(Int.max, width: Int.max)) {
            XCTAssertEqual($0 as? ImportedSurfaceError, .copyLimitExceeded)
        }
        XCTAssertThrowsError(try budget.charge(-1))
        XCTAssertThrowsError(try budget.charge(0, width: 0))
        XCTAssertThrowsError(try ImportedSurfaceCopy.identity(nil, budget: &budget)) {
            XCTAssertEqual($0 as? ImportedSurfaceError, .invalidIdentity)
        }
        for text in ["", String(repeating: "a", count: 39)] {
            XCTAssertThrowsError(try text.withCString { try ImportedSurfaceCopy.identity($0, budget: &budget) })
        }
        XCTAssertEqual(
            ImportedSurfaceComponent(id: "a", kind: .original), ImportedSurfaceComponent(id: "a", kind: .original))
        XCTAssertNotEqual(
            ImportedSurfaceComponent(id: "a", kind: .original), ImportedSurfaceComponent(id: "a", kind: .generated))
        XCTAssertNotEqual(
            ImportedSurfaceComponent(id: "é", kind: .original),
            ImportedSurfaceComponent(id: "e\u{301}", kind: .original))
    }

    func test_should_validate_options_and_report_actionable_errors() throws {
        for options in [
            ImportedSurfaceOptions(maximumNativePayloadBytes: -1), .init(maximumNativePayloadBytes: Int.max),
            .init(maximumCopiedPayloadBytes: 0), .init(maximumCopiedPayloadBytes: Int.max),
        ] {
            XCTAssertThrowsError(try ImportedSurfaceLoader.validate(dataCount: 0, options: options)) {
                XCTAssertEqual($0 as? ImportedSurfaceError, .invalidLimits)
            }
        }
        XCTAssertThrowsError(try ImportedSurfaceLoader.validate(dataCount: -1, options: .init()))
        XCTAssertThrowsError(
            try ImportedSurfaceLoader.validate(dataCount: MeshLoader.maximumFileSize + 1, options: .init())
        ) {
            XCTAssertEqual($0 as? ImportedSurfaceError, .archiveLimitExceeded)
        }
        for error in ImportedSurfaceError.allCases {
            XCTAssertFalse(try XCTUnwrap(error.errorDescription).isEmpty)
        }
    }
}
