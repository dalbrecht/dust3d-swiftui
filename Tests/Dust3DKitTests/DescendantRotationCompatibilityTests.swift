import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

final class DescendantRotationCompatibilityTests: XCTestCase {
    func testAllDescendantQuarterTurnsRemainReadableByPinnedCore() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let pivot = try XCTUnwrap(original.editorContents().nodes.dropFirst().first)
        for rotation in DescendantRotation.allCases {
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            _ = try await session.select(pivot.id)
            let result = try await session.rotateDescendants(rotation)
            let mesh = try MeshLoader.load(data: result.document.encoded())
            XCTAssertEqual(mesh.nodeCount, 3)
            XCTAssertEqual(mesh.partCount, 1)
            XCTAssertGreaterThan(mesh.triangleCount, 0)
            XCTAssertEqual(try result.document.node(id: pivot.id), pivot.value)
            let restored = try await session.undo()
            XCTAssertEqual(restored.document.encoded(), original.encoded())
        }
    }
}
