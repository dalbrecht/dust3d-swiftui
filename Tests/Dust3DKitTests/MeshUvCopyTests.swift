import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class MeshUvCopyTests: XCTestCase {
    func testValidatesCountsAndCheckedAggregateArraySizesBeforeUnsafeViews() throws {
        try counts().validate(maximumPayloadBytes: 1024)
        let minimum = MemoryLayout<Dust3DUvTriangle>.stride + MemoryLayout<Dust3DUvChart>.stride + 1
        try counts(payload: minimum).validate(maximumPayloadBytes: minimum)
        let invalid = [
            counts(triangles: -1), counts(triangles: 0), counts(charts: -1), counts(gradients: -1),
            counts(components: -1), counts(expanded: 0), counts(expanded: 4), counts(payload: -1),
            counts(payload: 0), counts(payload: 1025), counts(payload: minimum - 1),
            counts(charts: Int.max), counts(gradients: Int.max), counts(components: Int.max),
            counts(triangles: (Int.max - 1) / 3, expanded: Int.max - 1),
        ]
        for value in invalid {
            XCTAssertThrowsError(try value.validate(maximumPayloadBytes: 1024)) {
                XCTAssertEqual($0 as? MeshUvDataError, .invalidBufferCounts)
            }
        }
    }

    func testDecodesBoundedImageNamesWithoutRepairOrNormalization() throws {
        XCTAssertNil(try MeshUvCopy.imageIdentifier([0]))
        XCTAssertEqual(try MeshUvCopy.imageIdentifier(Array("image".utf8) + [0]), "image")
        XCTAssertEqual(
            try MeshUvCopy.imageIdentifier(Array(repeating: 122, count: 38) + [0]), String(repeating: "z", count: 38))
        for value in ["e\u{301}\u{327}", "e\u{327}\u{301}"] {
            let result = try XCTUnwrap(MeshUvCopy.imageIdentifier(Array(value.utf8) + [0]))
            XCTAssertTrue(result.utf8.elementsEqual(value.utf8))
        }
        let invalidBuffers: [[UInt8]] = [
            [], [255, 0], Array(repeating: 65, count: 39), Array(repeating: 65, count: 39) + [0],
        ]
        for bytes in invalidBuffers {
            XCTAssertThrowsError(try MeshUvCopy.imageIdentifier(bytes)) {
                XCTAssertEqual($0 as? MeshUvDataError, .invalidIdentity)
            }
        }
    }

    func testComponentIdentityFailuresPreserveTheirTypedCause() throws {
        let identifier = "{zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz}"
        try identifier.withCString { pointer in
            XCTAssertEqual(try MeshUvCopy.componentIdentifier(pointer), identifier)
        }
        XCTAssertThrowsError(try MeshUvCopy.componentIdentifier(nil)) {
            XCTAssertEqual(($0 as? MeshLoadingError)?.status, 3)
            XCTAssertTrue(($0 as? MeshLoadingError)?.message.contains("invalidIdentity") == true)
        }
    }

    func testCancellationAfterNativeGenerationDoesNotPublishCopiedMetadata() async throws {
        let data = try Data(
            contentsOf: XCTUnwrap(
                Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures")))
        let task = Task {
            var options = Dust3DUvOptions(
                struct_size: MemoryLayout<Dust3DUvOptions>.size, maximum_payload_bytes: 0,
                texture_size: 0, images: nil, image_count: 0)
            var error = Dust3DError()
            let native = data.withUnsafeBytes {
                dust3d_uv_mesh_load($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &options, &error)
            }
            let owner = try XCTUnwrap(native)
            defer { dust3d_uv_mesh_destroy(owner) }
            let geometry = try XCTUnwrap(dust3d_uv_mesh_geometry(owner))
            withUnsafeCurrentTask { $0?.cancel() }
            return try MeshUvCopy.copy(
                owner, geometry: geometry, maximumPayloadBytes: Int(DUST3D_DEFAULT_UV_PAYLOAD_BYTES))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled UV copies must not publish data")
        } catch is CancellationError {}
    }

    private func counts(
        triangles: Int = 1, charts: Int = 1, gradients: Int = 0, components: Int = 1,
        expanded: Int = 3, payload: Int = 1024
    ) -> MeshUvCounts {
        MeshUvCounts(
            triangles: triangles, charts: charts, gradients: gradients, components: components,
            expandedVertices: expanded, payload: payload)
    }
}
