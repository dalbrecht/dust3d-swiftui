import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor
final class QtXMLFilePasteSessionTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
    }

    func testPasteUsesOneUndoAndRemapsTheGraphWithoutChangingTheSource() async throws {
        let source = try source()
        let session = EditorSession()
        let before = try await session.open(data: source.encoded())
        let pasted = try await session.pasteQtXMLFile(source.modelXML, target: .init(snapshot: before))
        XCTAssertEqual(pasted.nodes.count, 2)
        let node = try XCTUnwrap(pasted.selectedNodes.first)
        XCTAssertNotEqual(node.id, "a")
        XCTAssertEqual(node.value.position.y, 0.04)
        XCTAssertTrue(pasted.canUndo)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), pasted.document.encoded())
    }

    func testDelayedPasteRejectsSelectionRevisionAndAnotherDocument() async throws {
        let source = try source()
        let first = EditorSession()
        let second = EditorSession()
        let original = try await first.open(data: source.encoded())
        let target = CanvasAdjustmentTarget(snapshot: original)
        _ = try await first.select("a")
        _ = try await first.select(nil)
        let other = try await second.open(data: source.encoded())
        for session in [first, second] {
            do {
                _ = try await session.pasteQtXMLFile(source.modelXML, target: target)
                XCTFail("A retained file paste changed another source")
            } catch {
                XCTAssertEqual(error as? QtXMLFilePasteError, .staleTarget)
            }
            let current = try await session.select(nil)
            XCTAssertEqual(current.document.encoded(), source.encoded())
            XCTAssertFalse(current.canUndo)
        }
        XCTAssertNotEqual(original.documentIdentity, other.documentIdentity)
    }

    func testFilePasteWithExplicitMissingGroupRejectsBeforeGraphMutation() async throws {
        let original = try source()
        let session = EditorSession()
        let before = try await session.open(data: original.encoded())
        do {
            _ = try await session.pasteQtXMLFile(
                original.modelXML, target: .init(snapshot: before), parentID: "missing")
            XCTFail("Missing destination fell back to root")
        } catch {
            XCTAssertEqual(error as? DocumentError, .invalidComponentStructure)
        }
        let after = try await session.select(nil)
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertFalse(after.canUndo)
    }

    func testEmptyFragmentAndMalformedInputPreserveHistoryAndPasteOrdinal() async throws {
        let source = try source()
        let session = EditorSession()
        let opened = try await session.open(data: source.encoded())
        let first = try await session.pasteQtXMLFile(source.modelXML, target: .init(snapshot: opened))
        let before = try await session.undo()
        let target = CanvasAdjustmentTarget(snapshot: before)
        let noChange = try await session.pasteQtXMLFile(Data("<canvas rigType='Biped'/>".utf8), target: target)
        XCTAssertEqual(noChange.document.encoded(), before.document.encoded())
        XCTAssertEqual(noChange.documentRevision, before.documentRevision)
        XCTAssertEqual(noChange.selectionRevision, before.selectionRevision)
        XCTAssertTrue(noChange.canRedo)
        do {
            _ = try await session.pasteQtXMLFile(Data("<canvas><nodes>".utf8), target: target)
            XCTFail("Malformed XML was accepted")
        } catch {
            XCTAssertEqual(error as? DocumentError, .invalidXML)
        }
        let restored = try await session.redo()
        XCTAssertEqual(restored.document.encoded(), first.document.encoded())
        let next = try await session.pasteQtXMLFile(source.modelXML, target: .init(snapshot: restored))
        XCTAssertEqual(next.selectedNodes.first?.value.position.y, 0.08)
    }
}
