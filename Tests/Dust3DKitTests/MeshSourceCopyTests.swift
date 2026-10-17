import Dust3DEngine
import XCTest

@testable import Dust3DKit

@MainActor
final class MeshSourceCopyTests: XCTestCase {
    func testCopiesBoundedOpaqueIdentifiersWithoutRepair() throws {
        XCTAssertEqual(try identifier(Array("opaque-ID".utf8) + [0]), "opaque-ID")
        XCTAssertEqual(try identifier(Array(repeating: UInt8(122), count: 38) + [0]), String(repeating: "z", count: 38))
        XCTAssertEqual(try identifier(Array("é".utf8) + [0]), "é")
        for value in ["e\u{301}\u{327}", "e\u{327}\u{301}"] {
            XCTAssertTrue(try identifier(Array(value.utf8) + [0]).utf8.elementsEqual(value.utf8))
        }
        XCTAssertThrowsError(try MeshSourceCopy.identifier(nil)) {
            XCTAssertEqual($0 as? MeshSourceDataError, .invalidIdentity)
        }
        for bytes in [[UInt8(0)], [255, 0], Array(repeating: 65, count: 39)] {
            XCTAssertThrowsError(try identifier(bytes)) { XCTAssertEqual($0 as? MeshSourceDataError, .invalidIdentity) }
        }
    }

    func testValidatesCountsBeforeConstructingUnsafeViews() throws {
        try counts().validate(maximumPayloadBytes: 1024)
        try counts(influences: 0, identities: 0, nodes: 0, payload: 72).validate(maximumPayloadBytes: 72)
        let invalid = [
            counts(corners: -1), counts(corners: 2), counts(expanded: 0), counts(expanded: 4),
            counts(influences: -1), counts(influences: Int.max), counts(identities: -1),
            counts(identities: 2), counts(nodes: -1), counts(payload: -1), counts(payload: 0),
            counts(payload: Int.max), counts(payload: 71), counts(payload: 95), counts(payload: 96),
            counts(corners: Int.max, expanded: Int.max),
        ]
        for value in invalid {
            XCTAssertThrowsError(try value.validate(maximumPayloadBytes: 1024)) {
                XCTAssertEqual($0 as? MeshSourceDataError, .invalidBufferCounts)
            }
        }
    }

    func testCancellationAfterNativeGenerationDoesNotPublishHints() async throws {
        let data = try Data(
            contentsOf: XCTUnwrap(
                Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures")))
        let task = Task {
            var options = Dust3DSourceOptions(
                struct_size: MemoryLayout<Dust3DSourceOptions>.size, maximum_payload_bytes: 0)
            var error = Dust3DError()
            let native = data.withUnsafeBytes {
                dust3d_sourced_mesh_load($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &options, &error)
            }
            let owner = try XCTUnwrap(native)
            defer { dust3d_sourced_mesh_destroy(owner) }
            let geometry = try XCTUnwrap(dust3d_sourced_mesh_geometry(owner))
            withUnsafeCurrentTask { $0?.cancel() }
            return try MeshSourceCopy.copy(
                owner, geometry: geometry, maximumPayloadBytes: MeshGenerationSession.defaultSourcePayloadBytes)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled metadata copies must fail without publishing values")
        } catch is CancellationError {}
    }

    private func identifier(_ bytes: [UInt8]) throws -> String {
        try bytes.map { CChar(bitPattern: $0) }.withUnsafeBufferPointer {
            try MeshSourceCopy.identifier($0.baseAddress)
        }
    }

    private func counts(
        corners: Int = 3, influences: Int = 1, identities: Int = 1, expanded: Int = 3, nodes: Int = 1,
        payload: Int = 1024
    ) -> MeshSourceCounts {
        MeshSourceCounts(
            corners: corners, influences: influences, identities: identities, expandedVertices: expanded, nodes: nodes,
            payload: payload)
    }
}
