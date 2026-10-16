import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

final class QtClipboardCompatibilityTests: XCTestCase {
    func testSnapshotTextPasteGeneratesCapsuleAndUndoesExactly() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "xml", subdirectory: "Fixtures"))
        let xml = try Data(contentsOf: url)
        let session = EditorSession()
        let empty = Dust3DDocument.emptyArchive()
        _ = try await session.open(data: empty)
        let result = try await session.paste(snapshotXML: xml)
        XCTAssertEqual(result.selectedIDs.count, 3)
        let mesh = try MeshLoader.load(data: result.document.encoded())
        XCTAssertEqual(mesh.nodeCount, 3)
        XCTAssertEqual(mesh.partCount, 1)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        let copy = try await session.copyRepresentations(identifier: "copy")
        let native = try NodeClipboardPayload(data: copy.native)
        XCTAssertEqual(native.fragment.document.modelXML, copy.snapshotXML)
        let textArchive = try Dust3DDocument(snapshotXML: copy.snapshotXML)
        XCTAssertEqual(try MeshLoader.load(data: textArchive.encoded()).triangleCount, mesh.triangleCount)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), empty)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), result.document.encoded())
    }
}
