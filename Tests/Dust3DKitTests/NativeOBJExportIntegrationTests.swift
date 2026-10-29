import Foundation
import XCTest

@testable import Dust3DKit

/// The existing licensed Capsule positive only; no native failure/cancellation/import probes.
@MainActor
final class NativeOBJExportIntegrationTests: XCTestCase {
    func testShouldExportExistingLicensedCapsuleWithOwnedOriginalGeometry() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let archive = try Data(contentsOf: url)
        let encoder = NativeOBJExportEncoder()
        let output = try await encoder.encode(archive: archive, format: .obj)
        XCTAssertTrue(output.warning.isEmpty)
        let text = try XCTUnwrap(String(data: output.bytes, encoding: .utf8))
        var vertices = 0
        var faces: [[Int]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let record = fields.first, !record.hasPrefix("#") else { continue }
            switch record {
            case "v":
                XCTAssertEqual(fields.count, 4)
                for field in fields.dropFirst() { XCTAssertTrue(try XCTUnwrap(Double(field)).isFinite) }
                vertices += 1
            case "f":
                XCTAssertTrue(fields.count == 4 || fields.count == 5)
                faces.append(try fields.dropFirst().map { try XCTUnwrap(Int($0)) })
            default: XCTFail("Original-geometry OBJ must not imply material/UV/rig export: \(record)")
            }
        }
        XCTAssertGreaterThan(vertices, 0)
        XCTAssertFalse(faces.isEmpty)
        for face in faces { XCTAssertTrue(face.allSatisfy { (1...vertices).contains($0) }) }
        let retained = Array(output.bytes)
        _ = try await encoder.encode(archive: archive, format: .obj)
        XCTAssertEqual(Array(output.bytes), retained)
        XCTAssertEqual(try Data(contentsOf: url), archive)
    }
}
