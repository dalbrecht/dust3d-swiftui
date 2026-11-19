import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EditableGeometrySelectionTests: XCTestCase {
    private let protectedPart = "{aaaaaaaa-aaaa-4aaa-8aaa-000000000001}"
    private let protectedComponent = "{bbbbbbbb-bbbb-4bbb-8bbb-000000000001}"
    private let firstProtected = "{11111111-1111-4111-8111-000000000001}"
    private let lastProtected = "{11111111-1111-4111-8111-000000000002}"
    private let protectedEdge = "{44444444-4444-8444-8444-000000000001}"

    @MainActor func testCopiedCapsuleSelectsOnlyEditableGeometryAndDeletesInOneUndoStep() async throws {
        let source = try document()
        let contents = try source.editorContents()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let inspected = try await session.selectAll()
        XCTAssertEqual(inspected.selectedIDs.count, 5)
        XCTAssertEqual(inspected.selectedEdgeIDs.count, 3)
        XCTAssertFalse(inspected.canDeleteSelection)

        let selected = try await session.selectEditableGeometry(target: .init(snapshot: inspected))
        XCTAssertEqual(selected.selectedIDs, Set(contents.nodes.filter(\.isEditable).map(\.id)))
        XCTAssertEqual(selected.selectedEdgeIDs, Set(contents.edges.filter { $0.id != protectedEdge }.map(\.id)))
        XCTAssertEqual(selected.document.encoded(), source.encoded())
        XCTAssertEqual(selected.previewIdentity, inspected.previewIdentity)
        XCTAssertFalse(selected.canUndo)
        XCTAssertTrue(selected.canDeleteSelection)

        let deleted = try await session.deleteSelection()
        XCTAssertEqual(deleted.nodes.map(\.id), [firstProtected, lastProtected])
        XCTAssertEqual(deleted.edges.map(\.id), [protectedEdge])
        XCTAssertEqual(deleted.parts.map(\.id), [protectedPart])
        XCTAssertEqual(try deleted.document.components().map(\.id), [protectedComponent])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    @MainActor func testMalformedEdgeOwnerDoesNotExposeItsEndpointsForBulkDelete() async throws {
        let source = try document()
        let model = try XMLDocument(data: source.modelXML)
        let edge = try XCTUnwrap(
            model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge").first)
        edge.attribute(forName: "partId")?.stringValue = protectedPart
        let malformed = try Dust3DDocument(snapshotXML: model.xmlData(options: [.nodePreserveAll]))
        let state = try EditorState(document: malformed)
        XCTAssertFalse(state.snapshot.canSelectEditableGeometry)
    }

    @MainActor func testLockedPartAndNodeCutFaceReferencesProtectEditableProfile() async throws {
        let source = try document()
        let profile = try XCTUnwrap(try source.editorContents().parts.first).id
        for nodeOverride in [false, true] {
            let model = try XMLDocument(data: source.modelXML)
            let element = try XCTUnwrap(
                model.nodes(forXPath: "//*[@id='\(nodeOverride ? firstProtected : protectedPart)']").first
                    as? XMLElement)
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "cutFace"
            attribute.stringValue = profile
            element.addAttribute(attribute)
            let linked = try Dust3DDocument(snapshotXML: model.xmlData(options: [.nodePreserveAll]))
            let session = EditorSession()
            let opened = try await session.open(data: linked.encoded())
            XCTAssertFalse(opened.canSelectEditableGeometry)
            let selected = try await session.selectEditableGeometry(target: .init(snapshot: opened))
            XCTAssertEqual(selected.selectedIDs, [])
            XCTAssertEqual(selected.selectedEdgeIDs, [])
            XCTAssertEqual(selected.document.encoded(), linked.encoded())
            XCTAssertFalse(selected.canUndo)
        }
    }

    private func document() throws -> Dust3DDocument {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        return try Dust3DDocument(data: Data(contentsOf: url))
            .applying(
                .addNode(
                    id: firstProtected, partID: protectedPart, componentID: protectedComponent,
                    position: .init(x: 2, y: 0, z: 0), radius: 0.1)
            )
            .applying(
                .addNode(
                    id: lastProtected, partID: protectedPart, componentID: nil,
                    position: .init(x: 2, y: 1, z: 0), radius: 0.1)
            )
            .applying(.addEdge(id: protectedEdge, from: firstProtected, to: lastProtected))
            .applying(.setPartState(id: protectedPart, property: .locked, value: true))
    }
}
