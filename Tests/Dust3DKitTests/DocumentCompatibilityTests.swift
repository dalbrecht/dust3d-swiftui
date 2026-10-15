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

    func testReversedChainIsReadableByPinnedNativeEngine() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let ids = try original.editorContents().edges.map(\.id)
        let reversed = try original.applying(.reverseEdges(ids))
        let mesh = try MeshLoader.load(data: reversed.encoded())
        XCTAssertEqual(mesh.nodeCount, 3)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertEqual(mesh.triangleCount, try MeshLoader.load(data: original.encoded()).triangleCount)
        var history = DocumentHistory(document: original)
        try history.apply(.reverseEdges(ids))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
    }

    func testRepositorySwordPreservesAllBytes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Sword", withExtension: "ds3", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(try Dust3DDocument(data: data).encoded(), data)
    }
    func testNewGraphAndTopologyUndoRemainReadableByPinnedEngine() throws {
        let first = "{11111111-1111-4111-8111-111111111111}"
        let second = "{22222222-2222-4222-8222-222222222222}"
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        var history = DocumentHistory(document: try Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        try history.beginTransaction()
        try history.apply(
            .addNode(
                id: first, partID: part, componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}",
                position: .init(x: 0.5, y: 0.25, z: 1), radius: 0.1))
        try history.apply(
            .addNode(id: second, partID: part, componentID: nil, position: .init(x: 0.5, y: 0.75, z: 1), radius: 0.1))
        try history.apply(.addEdge(id: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", from: first, to: second))
        try history.endTransaction()
        let mesh = try MeshLoader.load(data: history.document.encoded())
        XCTAssertEqual(mesh.nodeCount, 2)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        try history.apply(.removeNode(id: second))
        XCTAssertTrue(history.undo())
        let restored = try MeshLoader.load(data: history.document.encoded())
        XCTAssertEqual(restored.triangleCount, mesh.triangleCount)
        XCTAssertEqual(restored.nodeCount, 2)
    }

    func testDeletingLastNodePreservesEmptyPartWithoutBreakingOtherParts() throws {
        let first = "{11111111-1111-4111-8111-111111111111}"
        let second = "{22222222-2222-4222-8222-222222222222}"
        let empty = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let one = try empty.applying(
            .addNode(
                id: first, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let two = try one.applying(
            .addNode(
                id: second, partID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                componentID: "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}", position: .init(x: 1, y: 0, z: 0), radius: 0.1))
        let deleted = try two.applying(.removeNode(id: first))
        let mesh = try MeshLoader.load(data: deleted.encoded())
        XCTAssertEqual(mesh.nodeCount, 1)
        XCTAssertEqual(mesh.partCount, 2)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
    }

}
