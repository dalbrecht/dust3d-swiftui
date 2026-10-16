import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class QtClipboardSessionTests: XCTestCase {
    @MainActor func testRepeatedQtPastesAreAtomicUndoableAndResetOnOpen() async throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let first = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(first.selectedNodes.first?.value.position.y, 0.04)
        let second = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(second.selectedNodes.first?.value.position.y, 0.08)
        _ = try await session.undo()
        do {
            _ = try await session.paste(snapshotXML: Data("<canvas/>".utf8))
            XCTFail("Empty Qt clipboard must reject")
        } catch {}
        let restored = try await session.redo()
        XCTAssertEqual(restored.document.encoded(), second.document.encoded())
        let third = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(third.selectedNodes.first?.value.position.y, 0.12)
        _ = try await session.open(data: source.encoded())
        let reset = try await session.paste(snapshotXML: source.modelXML)
        XCTAssertEqual(reset.selectedNodes.first?.value.position.y, 0.04)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        _ = try await session.select("a")
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0])
        _ = try await session.apply([.setReferenceImagePNG(png)])
        let representations = try await session.copyRepresentations(identifier: "copy")
        XCTAssertEqual(try NodeClipboardPayload(data: representations.native).fragment.document.referenceImagePNG, png)
        XCTAssertNil(try Dust3DDocument(snapshotXML: representations.snapshotXML).referenceImagePNG)
        XCTAssertEqual(
            try NodeClipboardPayload(data: representations.native).fragment.document.modelXML,
            representations.snapshotXML)
        XCTAssertEqual(try Dust3DDocument(snapshotXML: representations.snapshotXML).editorContents().nodes.count, 1)
    }
}
