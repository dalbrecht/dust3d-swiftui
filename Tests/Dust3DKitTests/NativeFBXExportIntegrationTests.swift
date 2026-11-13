import Foundation
import XCTest

@testable import Dust3DKit

/// Ordinary licensed Capsule through both static FBX modes.
@MainActor
final class NativeFBXExportIntegrationTests: XCTestCase {
    func testLicensedCapsuleExportsProceduralAtlasThroughOwnedFBXRoute() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let archive = try Data(contentsOf: url)
        let artifact = try await NativeGeometryExportEncoder().encode(archive: archive, format: .fbxTextured)
        XCTAssertTrue(artifact.bytes.starts(with: "Kaydara FBX Binary".utf8))
        XCTAssertNotNil(artifact.bytes.range(of: Data("LayerElementUV".utf8)))
        XCTAssertNotNil(artifact.bytes.range(of: Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])))
        XCTAssertEqual(try Data(contentsOf: url), archive)
        if let directory = ProcessInfo.processInfo.environment["DUST3D_FBX_QA_OUTPUT_DIR"] {
            let target = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(
                "CapsuleTextured.fbx")
            try artifact.bytes.write(to: target, options: .atomic)
        }
    }

    func testLicensedCapsuleProducesOwnedStaticBinaryFBXAcrossOwnerLifetimes() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let archive = try Data(contentsOf: url)
        let encoder = NativeGeometryExportEncoder()
        let output = try await encoder.encode(archive: archive, format: .fbx)
        XCTAssertTrue(output.bytes.starts(with: "Kaydara FBX Binary".utf8))
        XCTAssertGreaterThan(output.bytes.count, 27)
        XCTAssertTrue(output.warning.isEmpty)
        let retained = Array(output.bytes)
        let other = try NativeFBXExportEncoder(
            maximumGeometryPayloadBytes: 64 * 1024 * 1024, maximumOutputPayloadBytes: 64 * 1024 * 1024)
        _ = try await other.encode(archive: archive, format: .fbx)
        XCTAssertEqual(Array(output.bytes), retained)
        XCTAssertEqual(try Data(contentsOf: url), archive)
        if let directory = ProcessInfo.processInfo.environment["DUST3D_FBX_QA_OUTPUT_DIR"] {
            let target = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(
                "CapsuleGeometry.fbx")
            try output.bytes.write(to: target, options: .atomic)
            let reference = try await encoder.encode(archive: archive, format: .obj)
            try reference.bytes.write(
                to: target.deletingPathExtension().appendingPathExtension("obj"), options: .atomic)
        }
    }
}
