import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor
final class QtPasteCutFaceTests: XCTestCase {
    private let missing = "{11111111-1111-4111-8111-111111111111}"
    private let existing = "{22222222-2222-4222-8222-222222222222}"
    private let included = "{33333333-3333-4333-8333-333333333333}"

    private func destination() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id="profile-node" partId="\(existing)" x="0" y="0" z="0" radius=".1"/></nodes>
                <parts><part id="\(existing)" target="CutFace" cutFace="\(missing)"/></parts></canvas>
                """.utf8))
    }

    private func fragment() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas>
                <nodes>
                  <node id="a" partId="p" x="0" y="0" z="0" radius=".1" cutFace="\(missing)" cutRotation=".5"/>
                  <node id="b" partId="q" x="1" y="0" z="0" radius=".1" cutFace="Triangle" cutRotation=".3"/>
                  <node id="c" partId="r" x="2" y="0" z="0" radius=".1" cutFace="FuturePreset"/>
                  <node id="d" partId="\(included)" x="3" y="0" z="0" radius=".1"/>
                </nodes>
                <parts>
                  <part id="p" name="Missing" cutFace="\(missing)" cutRotation=".25"/>
                  <part id="q" name="Existing" cutFace="\(existing)"/>
                  <part id="r" name="Included" cutFace="\(included)"/>
                  <part id="\(included)" name="Profile" target="CutFace"/>
                </parts>
                </canvas>
                """.utf8))
    }

    func testInteractiveQtPasteClearsOnlyMissingLinksAndUndoesExactly() async throws {
        let original = try destination()
        let source = try fragment()
        let session = EditorSession()
        let initial = try await session.open(data: original.encoded())
        let pasted = try await session.pasteQtXMLFile(
            source.modelXML, target: .init(snapshot: initial), clearsMissingCutFaces: true)
        let xml = try XCTUnwrap(XMLDocument(data: pasted.document.modelXML).rootElement())
        let parts = xml.elements(forName: "parts").flatMap { $0.elements(forName: "part") }
        let missingPart = try XCTUnwrap(parts.first { $0.attribute(forName: "name")?.stringValue == "Missing" })
        let existingPart = try XCTUnwrap(parts.first { $0.attribute(forName: "name")?.stringValue == "Existing" })
        let includedPart = try XCTUnwrap(parts.first { $0.attribute(forName: "name")?.stringValue == "Included" })
        let profile = try XCTUnwrap(parts.first { $0.attribute(forName: "name")?.stringValue == "Profile" })
        XCTAssertNil(missingPart.attribute(forName: "cutFace"))
        XCTAssertEqual(missingPart.attribute(forName: "cutRotation")?.stringValue, ".25")
        XCTAssertEqual(existingPart.attribute(forName: "cutFace")?.stringValue, existing)
        XCTAssertEqual(
            includedPart.attribute(forName: "cutFace")?.stringValue, profile.attribute(forName: "id")?.stringValue)
        XCTAssertNotEqual(includedPart.attribute(forName: "cutFace")?.stringValue, included)
        XCTAssertEqual(
            parts.first { $0.attribute(forName: "id")?.stringValue == existing }?.attribute(forName: "cutFace")?
                .stringValue, missing)
        let nodes = xml.elements(forName: "nodes").flatMap { $0.elements(forName: "node") }
        let missingNode = try XCTUnwrap(
            nodes.first {
                $0.attribute(forName: "partId")?.stringValue == missingPart.attribute(forName: "id")?.stringValue
            })
        XCTAssertNil(missingNode.attribute(forName: "cutFace"))
        XCTAssertNil(missingNode.attribute(forName: "cutRotation"))
        XCTAssertTrue(nodes.contains { $0.attribute(forName: "cutFace")?.stringValue == "FuturePreset" })
        XCTAssertTrue(nodes.contains { $0.attribute(forName: "cutFace")?.stringValue == "Triangle" })
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)

        let clipboard = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertFalse(String(decoding: clipboard.document.modelXML, as: UTF8.self).contains("cutRotation=\".5\""))
    }

    func testInteractiveQtPasteClearsAliasesThatDoNotResolveExactly() async throws {
        let existingBare = existing.dropFirst().dropLast()
        let includedBare = included.dropFirst().dropLast()
        let source = String(decoding: try fragment().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "cutFace=\"\(existing)\"", with: "cutFace=\"\(existingBare)\"")
            .replacingOccurrences(of: "cutFace=\"Triangle\"", with: "cutFace=\"\(existingBare)\"")
            .replacingOccurrences(of: "id=\"\(included)\"", with: "id=\"\(includedBare)\"")
            .replacingOccurrences(of: "partId=\"\(included)\"", with: "partId=\"\(includedBare)\"")
        let session = EditorSession()
        let original = try destination()
        _ = try await session.open(data: original.encoded())
        let pasted = try await session.paste(snapshotXML: Data(source.utf8))
        let xml = try XCTUnwrap(XMLDocument(data: pasted.document.modelXML).rootElement())
        let parts = xml.elements(forName: "parts").flatMap { $0.elements(forName: "part") }
        let existingPart = try XCTUnwrap(parts.first { $0.attribute(forName: "name")?.stringValue == "Existing" })
        let includedPart = try XCTUnwrap(parts.first { $0.attribute(forName: "name")?.stringValue == "Included" })
        XCTAssertNil(existingPart.attribute(forName: "cutFace"))
        XCTAssertNil(includedPart.attribute(forName: "cutFace"))
        let node = try XCTUnwrap(
            xml.elements(forName: "nodes").flatMap { $0.elements(forName: "node") }.first {
                $0.attribute(forName: "partId")?.stringValue == existingPart.attribute(forName: "id")?.stringValue
            })
        XCTAssertNil(node.attribute(forName: "cutFace"))
        XCTAssertNil(node.attribute(forName: "cutRotation"))
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
    }

    func testNativeAndNoninteractivePasteKeepAuthoredUnresolvedProfileMetadata() async throws {
        let source = try fragment()
        let selection = Set(try source.editorContents().nodes.map(\.id))
        let clipboard = try NodeClipboard(document: source, selectedNodeIDs: selection)
        let payload = try NodeClipboardPayload(fragment: clipboard, identifier: "native").encoded()
        let session = EditorSession()
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        let pasted = try await session.paste(data: payload)
        let xml = String(decoding: pasted.document.modelXML, as: UTF8.self)
        XCTAssertTrue(xml.contains("cutFace=\"\(missing)\""))
        XCTAssertTrue(xml.contains("cutRotation=\".5\""))

        let initial = try await session.open(data: Dust3DDocument.emptyArchive())
        let startup = try await session.pasteQtXMLFile(source.modelXML, target: .init(snapshot: initial))
        let startupXML = String(decoding: startup.document.modelXML, as: UTF8.self)
        XCTAssertTrue(startupXML.contains("cutFace=\"\(missing)\""))
        XCTAssertTrue(startupXML.contains("cutRotation=\".5\""))
    }
}
