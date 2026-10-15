import Dust3DDocument
import Dust3DKit
import Foundation
import XCTest

final class DocumentCompatibilityTests: XCTestCase {
    func testEditedArchiveIsReadableByPinnedNativeEngine() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let document = try Dust3DDocument(data: data)
        XCTAssertEqual(document.encoded(), data)
        let edited = try document.applying(
            .setNode(
                id: "{22222222-2222-4222-8222-222222222222}",
                position: .init(x: 0.5, y: 0.5, z: 1), radius: 0.2))
        let mesh = try MeshLoader.load(data: edited.encoded())
        XCTAssertEqual(mesh.nodeCount, 3)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
    }

    func testRepositorySwordPreservesAllBytes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Sword", withExtension: "ds3", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(try Dust3DDocument(data: data).encoded(), data)
    }
}
