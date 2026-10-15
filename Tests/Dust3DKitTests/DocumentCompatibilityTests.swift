import Dust3DDocument
import Dust3DEditorModel
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

    @MainActor func testSessionDisconnectionAndMiddleDeletionGenerateSplitMeshes() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let original = try Dust3DDocument(data: data)
        let contents = try original.editorContents()
        let edgeID = try XCTUnwrap(contents.edges.first?.id)
        let middleID = "{22222222-2222-4222-8222-222222222222}"
        for removeNode in [false, true] {
            let session = EditorSession()
            _ = try await session.open(data: data)
            _ = try await session.select(middleID)
            let result = try await (removeNode ? session.deleteSelection() : session.apply([.removeEdge(id: edgeID)]))
            let mesh = try MeshLoader.load(data: result.document.encoded())
            XCTAssertEqual(mesh.partCount, 2)
            XCTAssertEqual(mesh.nodeCount, removeNode ? 2 : 3)
            XCTAssertGreaterThan(mesh.triangleCount, 0)
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), data)
            XCTAssertFalse(undone.canUndo)
            let redone = try await session.redo()
            XCTAssertEqual(redone.document.encoded(), result.document.encoded())
            XCTAssertEqual(try MeshLoader.load(data: redone.document.encoded()).triangleCount, mesh.triangleCount)
        }
    }

    @MainActor func testSessionSplitsNamespacedArchivesWithoutInterpretingExtensionComponents() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let edgeID = try XCTUnwrap(try original.editorContents().edges.first?.id)
        for namespaced in [false, true] {
            let model = try XMLDocument(data: original.modelXML)
            if namespaced {
                let namespace = XMLNode(kind: .namespace)
                namespace.name = ""
                namespace.stringValue = "urn:future"
                model.rootElement()?.addNamespace(namespace)
            }
            model.rootElement()?.addChild(
                try XMLElement(
                    xmlString:
                        "<future><component linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' linkDataType='partId'/></future>"
                ))
            let xml = model.xmlData(options: [.nodePreserveAll])
            let header = "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/></ds3>"
            let prefix = "DUST3D 1.0 xml "
            let data =
                Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml
            let session = EditorSession()
            _ = try await session.open(data: data)
            let result = try await session.apply([.removeEdge(id: edgeID)])
            XCTAssertEqual(Set(result.nodes.compactMap(\.partID)).count, 2)
            let mesh = try MeshLoader.load(data: result.document.encoded())
            XCTAssertEqual(mesh.partCount, 2)
            XCTAssertGreaterThan(mesh.triangleCount, 0)
            let retained = try XMLDocument(data: result.document.modelXML).rootElement()?.elements(forName: "future")
                .first
            XCTAssertEqual(retained?.elements(forName: "component").count, 1)
            let restored = try await session.undo()
            XCTAssertEqual(restored.document.encoded(), data)
        }
    }

    @MainActor func testSplitPiecesCanRejoinThroughActorAndUndoRestoresSplit() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let original = try Dust3DDocument(data: data)
        let edge = try XCTUnwrap(try original.editorContents().edges.first)
        let session = EditorSession()
        _ = try await session.open(data: data)
        let split = try await session.apply([.removeEdge(id: edge.id)])
        let joined = try await session.apply([
            .joinNodes(id: "{99999999-9999-4999-8999-999999999999}", from: edge.toID, to: edge.fromID)
        ])
        let mesh = try MeshLoader.load(data: joined.document.encoded())
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertEqual(mesh.nodeCount, 3)
        XCTAssertEqual(mesh.triangleCount, try MeshLoader.load(data: data).triangleCount)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), split.document.encoded())
        XCTAssertEqual(try MeshLoader.load(data: restored.document.encoded()).partCount, 2)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), joined.document.encoded())
    }

    @MainActor func testEndpointExtensionUsesSuggestedPositionAndGeneratesMesh() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let session = EditorSession()
        _ = try await session.open(data: data)
        let firstID = "{11111111-1111-4111-8111-111111111111}"
        let selected = try await session.select(firstID)
        let partID = try XCTUnwrap(selected.selectedNode?.partID)
        let newID = "{44444444-4444-4444-8444-444444444444}"
        let result = try await session.apply(
            [
                .addNode(
                    id: newID, partID: partID, componentID: nil, position: selected.nextNodePosition, radius: 0.12),
                .joinNodes(id: "{99999999-9999-4999-8999-999999999999}", from: firstID, to: newID),
            ], selecting: newID)
        let mesh = try MeshLoader.load(data: result.document.encoded())
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertEqual(mesh.nodeCount, 4)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertEqual(try result.document.node(id: newID).position.y, 0)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), data)
        XCTAssertFalse(restored.canUndo)
    }

    func testCopiedCapsulePastesIntoBlankArchiveWithPinnedEngine() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let contents = try original.editorContents()
        for selection in [Set(contents.nodes.map(\.id)), Set(contents.nodes.prefix(2).map(\.id))] {
            let clipboard = try original.copyingNodes(selection)
            let identities = Dictionary(
                uniqueKeysWithValues: clipboard.identifiers.map { ($0, "{\(UUID().uuidString.lowercased())}") })
            let blank = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
            let pasted = try blank.applying(
                .pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0, z: 0)))
            let mesh = try MeshLoader.load(data: pasted.encoded())
            XCTAssertEqual(mesh.nodeCount, selection.count)
            XCTAssertEqual(mesh.partCount, 1)
            XCTAssertGreaterThan(mesh.triangleCount, 0)
            if selection.count == contents.nodes.count {
                XCTAssertEqual(mesh.triangleCount, try MeshLoader.load(data: original.encoded()).triangleCount)
            }
        }
    }

    func testClipboardAdaptsGraphNamespacesForPinnedEngine() throws {
        func archive(_ xml: XMLDocument) throws -> Dust3DDocument {
            let model = xml.xmlData(options: [.nodePreserveAll])
            let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
            let prefix = "DUST3D 1.0 xml "
            return try Dust3DDocument(
                data: Data(
                    (prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                    + model)
        }
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let model = try XMLDocument(data: original.modelXML)
        let namespace = XMLNode(kind: .namespace)
        namespace.name = ""
        namespace.stringValue = "urn:source"
        model.rootElement()?.addNamespace(namespace)
        let source = try archive(model)
        let clipboard = try source.copyingNodes(Set(try source.editorContents().nodes.map(\.id)))
        let blank = try XMLDocument(data: Dust3DDocument(data: Dust3DDocument.emptyArchive()).modelXML)
        let destinationNamespace = XMLNode(kind: .namespace)
        destinationNamespace.name = ""
        destinationNamespace.stringValue = "urn:destination"
        blank.rootElement()?.addNamespace(destinationNamespace)
        let destination = try archive(blank)
        let identities = Dictionary(
            uniqueKeysWithValues: clipboard.identifiers.map { ($0, "{\(UUID().uuidString.lowercased())}") })
        let pasted = try destination.applying(
            .pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0, z: 0)))
        let mesh = try MeshLoader.load(data: pasted.encoded())
        XCTAssertEqual(mesh.nodeCount, 3)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertEqual(mesh.triangleCount, try MeshLoader.load(data: original.encoded()).triangleCount)
    }

    @MainActor func testClipboardActorPartitionsReadonlyCapsuleCopyForPinnedEngine() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let original = try Dust3DDocument(data: Data(contentsOf: url))
        let model = try XMLDocument(data: original.modelXML)
        let attribute = XMLNode(kind: .attribute)
        attribute.name = "locked"
        attribute.stringValue = "true"
        model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part").first?.addAttribute(attribute)
        let xml = model.xmlData(options: [.nodePreserveAll])
        let header = "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let data =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8) + xml
        let source = EditorSession()
        let opened = try await source.open(data: data)
        _ = try await source.select(Set([opened.nodes[0].id, opened.nodes[2].id]))
        let payload = try await source.copyPayload(identifier: "readonly-capsule")
        let target = EditorSession()
        _ = try await target.open(data: Dust3DDocument.emptyArchive())
        let pasted = try await target.paste(data: payload)
        XCTAssertEqual(pasted.selectedIDs.count, 2)
        XCTAssertTrue(pasted.nodes.allSatisfy { !$0.isEditable })
        let mesh = try MeshLoader.load(data: pasted.document.encoded())
        XCTAssertEqual(mesh.nodeCount, 2)
        XCTAssertEqual(mesh.partCount, 2)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        let restored = try await target.undo()
        XCTAssertEqual(restored.document.encoded(), Dust3DDocument.emptyArchive())
        let redone = try await target.redo()
        XCTAssertEqual(redone.document.encoded(), pasted.document.encoded())
    }

}
