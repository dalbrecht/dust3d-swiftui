import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class LegacyIslandConnectionTests: XCTestCase {
    @MainActor func testConnectRepairsLegacySamePartIslandsInOneUndoStep() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let before = try original.editorContents()
        XCTAssertEqual(before.nodes.count, 3)
        XCTAssertEqual(before.edges.count, 2)
        let owner = try XCTUnwrap(before.parts.first)
        let linkedComponent = try XCTUnwrap(try original.components().first)
        let disconnected = try original.applying(.removeEdges(before.edges.map(\.id)))
        let opaque = Data([19, 20, 21])
        let legacy = try archive(snapshot: disconnected.modelXML, opaque: opaque)
        let session = EditorSession()
        _ = try await session.open(data: legacy.encoded())
        let endpointIDs = Set(before.nodes.prefix(2).map(\.id))
        let selected = try await session.selectGraph(nodes: endpointIDs, edges: [])
        let target = NodeConnectionTarget(snapshot: selected)
        XCTAssertEqual(target.owners.count, 2)
        XCTAssertFalse(target.requiresOwnershipChoice)

        let connected = try await session.connectSelectedNodes(target: target, ownerID: before.nodes[0].id)

        XCTAssertEqual(connected.selectedIDs, endpointIDs)
        XCTAssertEqual(connected.nodes.map(\.id), before.nodes.map(\.id))
        XCTAssertEqual(connected.nodes.map(\.value), before.nodes.map(\.value))
        XCTAssertEqual(connected.parts.count, 2)
        XCTAssertEqual(connected.parts.first(where: { $0.id == owner.id }), owner)
        let components = try connected.document.components()
        XCTAssertEqual(components.count, 2)
        XCTAssertEqual(components.first(where: { $0.id == linkedComponent.id }), linkedComponent)
        let newOwner = try XCTUnwrap(connected.parts.first(where: { $0.id != owner.id }))
        XCTAssertEqual(connected.nodes.map(\.partID), [owner.id, owner.id, newOwner.id])
        let edge = try XCTUnwrap(connected.edges.first)
        XCTAssertEqual(connected.edges.count, 1)
        XCTAssertEqual(Set([edge.fromID, edge.toID]), endpointIDs)
        XCTAssertEqual(edge.partID, owner.id)
        XCTAssertEqual(connected.document.asset(named: "opaque.bin"), opaque)
        let cloned = try XCTUnwrap(components.first(where: { $0.partID == newOwner.id }))
        XCTAssertEqual(cloned.color, linkedComponent.color)
        XCTAssertEqual(cloned.smoothCutoffDegrees, linkedComponent.smoothCutoffDegrees)
        XCTAssertEqual(newOwner.modifierValue(.roundedEnds), owner.modifierValue(.roundedEnds))

        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), legacy.encoded())
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), connected.document.encoded())
    }

    @MainActor func testConnectDoesNotNormalizeIslandsWhenClosingALoopWithinOne() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let contents = try original.editorContents()
        let owner = try XCTUnwrap(contents.parts.first)
        let isolated = try original.applying(
            .addNode(
                id: "{99999999-9999-4999-8999-999999999999}", partID: owner.id, componentID: nil,
                position: .init(x: 1, y: 1, z: 1), radius: 0.1)
        )
        .applying(
            .addNode(
                id: "{88888888-8888-4888-8888-888888888888}", partID: owner.id, componentID: nil,
                position: .init(x: 2, y: 1, z: 1), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: isolated.encoded())
        let endpoints = Set([contents.nodes[0].id, contents.nodes[2].id])
        let selected = try await session.selectGraph(nodes: endpoints, edges: [])
        let target = NodeConnectionTarget(snapshot: selected)
        XCTAssertEqual(target.owners.count, 2)

        do {
            _ = try await session.connectSelectedNodes(target: target, ownerID: contents.nodes[0].id)
            XCTFail("A loop closure does not repair disconnected islands")
        } catch DocumentError.invalidNode {}
        let retained = try await session.selectGraph(nodes: endpoints, edges: [])
        XCTAssertEqual(retained.document.encoded(), isolated.encoded())
        XCTAssertFalse(retained.canUndo)
    }

    private func archive(snapshot: Data, opaque: Data) throws -> Dust3DDocument {
        let header = Data(
            """
            <ds3><model name="model.xml" offset="0" size="\(snapshot.count)"/><asset name="opaque.bin" offset="\(snapshot.count)" size="\(opaque.count)"/></ds3>
            """.utf8)
        let prefix = Data("DUST3D 1.0 xml \(String(format: "%010d", 26 + header.count))\n".utf8)
        return try Dust3DDocument(data: prefix + header + snapshot + opaque)
    }
}
