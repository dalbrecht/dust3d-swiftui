import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ReferenceImageSessionTests: XCTestCase {
    private func png() throws -> Data {
        try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    }
    func testImageOnlyActorTransactionPublishesAndUndoesWithoutGraphChanges() async throws {
        let original = Dust3DDocument.emptyArchive()
        let session = EditorSession()
        let start = try await session.open(data: original)
        let image = try png()
        let next = try await session.apply([.setReferenceImagePNG(image)])
        XCTAssertEqual(next.document.referenceImagePNG, image)
        XCTAssertTrue(next.nodes.isEmpty)
        XCTAssertTrue(next.canUndo)
        XCTAssertEqual(next.documentRevision, start.documentRevision + 1)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original)
        XCTAssertFalse(restored.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), next.document.encoded())
    }
    func testFailedMixedBatchPreservesArchiveAndRedo() async throws {
        let original = Dust3DDocument.emptyArchive()
        let session = EditorSession()
        _ = try await session.open(data: original)
        _ = try await session.apply([.setReferenceImagePNG(png())])
        _ = try await session.undo()
        do {
            _ = try await session.apply([
                .setReferenceImagePNG(png()), .setNode(id: "missing", position: .init(x: 0, y: 0, z: 0), radius: 0.1),
            ])
            XCTFail("The batch must reject atomically")
        } catch {
            XCTAssertEqual(error as? DocumentError, .missingNode("missing"))
        }
        let retained = try await session.select(nil)
        XCTAssertEqual(retained.document.encoded(), original)
        XCTAssertTrue(retained.canRedo)
        XCTAssertFalse(retained.canUndo)
    }
}
