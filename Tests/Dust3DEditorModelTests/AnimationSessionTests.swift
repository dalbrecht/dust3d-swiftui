import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class AnimationSessionTests: XCTestCase {
    func testCreateDuplicateAndHistoryUseFreshIdentitiesAndCurrentSourceSnapshots() async throws {
        let session = EditorSession()
        let original = try await session.open(data: Dust3DDocument.emptyArchive())
        let created = try await session.createAnimation(name: "Walk", type: "future")
        XCTAssertEqual(created.editor.documentIdentity, original.documentIdentity)
        XCTAssertGreaterThan(created.editor.documentRevision, original.documentRevision)
        let first = try XCTUnwrap(created.list.selectedRow)
        XCTAssertNotNil(UUID(uuidString: first.source.id.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))))
        XCTAssertEqual(first.title, "Walk")
        XCTAssertEqual(first.typeLabel, "future")
        XCTAssertTrue(created.editor.canUndo)
        let duplicate = try await session.duplicateAnimation(id: first.source.id, name: "Walk copy")
        let second = try XCTUnwrap(duplicate.list.selectedRow)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotNil(UUID(uuidString: second.source.id.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))))
        XCTAssertEqual(duplicate.list.rows.count, 2)
        let duplicatedBytes = duplicate.editor.document.encoded()
        _ = try await session.undo()
        let undone = try await session.animationSnapshot()
        XCTAssertNil(undone.list.selectedRow)
        XCTAssertEqual(undone.list.rows.count, 1)
        _ = try await session.redo()
        let redone = try await session.animationSnapshot()
        XCTAssertEqual(redone.editor.document.encoded(), duplicatedBytes)
        XCTAssertNil(redone.list.selectedRow, "Redo does not resurrect a transient selection")
        let before = redone.editor.document.encoded()
        do {
            _ = try await session.duplicateAnimation(id: first.source.id, name: "bad\nname")
            XCTFail("Invalid duplicate must reject atomically")
        } catch { XCTAssertEqual(error as? DocumentAnimationError, .invalidName) }
        let unchanged = try await session.animationSnapshot()
        XCTAssertEqual(unchanged.editor.document.encoded(), before)
        XCTAssertEqual(unchanged.editor.documentRevision, redone.editor.documentRevision)
    }

    func testHistoryPrunesRemovedSelectionWithoutIntermediateQueries() async throws {
        let session = EditorSession()
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        let created = try await session.createAnimation(name: "Walk", type: "future")
        let identifier = try XCTUnwrap(created.list.selectedRow?.source.id)
        _ = try await session.undo()
        _ = try await session.redo()
        let restoredCreation = try await session.animationSnapshot()
        XCTAssertEqual(restoredCreation.editor.document.encoded(), created.editor.document.encoded())
        XCTAssertNil(restoredCreation.list.selectedRow)

        _ = try await session.selectAnimation(identifier)
        _ = try await session.apply([.deleteAnimation(id: identifier)])
        _ = try await session.undo()
        let restoredDeletion = try await session.animationSnapshot()
        XCTAssertEqual(restoredDeletion.editor.document.encoded(), created.editor.document.encoded())
        XCTAssertNil(restoredDeletion.list.selectedRow)
    }

    func testSelectionIsTransientIndependentFromGraphAndByteExact() async throws {
        let first = "caf\u{e9}"
        let second = "cafe\u{301}"
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='\(first)'/><animation id='\(second)' name='' type=''/></animations></canvas>"
                    .utf8))
        let session = EditorSession()
        let opened = try await session.open(data: document.encoded())
        let selected = try await session.selectAnimation(second)
        XCTAssertEqual(selected.editor.documentRevision, opened.documentRevision)
        XCTAssertEqual(selected.editor.document.encoded(), document.encoded())
        XCTAssertFalse(selected.editor.canUndo)
        XCTAssertEqual(selected.list.rows.count, 2)
        XCTAssertEqual(Set(selected.list.rows.map(\.id)).count, 2)
        XCTAssertEqual(selected.list.selectedRow?.id, Array(second.utf8))
        XCTAssertEqual(selected.list.rows[0].title, "Animation 1")
        XCTAssertEqual(selected.list.rows[1].title, "Animation 2")
        XCTAssertEqual(selected.list.rows[0].typeLabel, "Unspecified type")
        _ = try await session.apply([
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1)
        ])
        _ = try await session.select("node")
        let graphSelected = try await session.animationSnapshot()
        XCTAssertEqual(graphSelected.editor.selectedID, "node")
        XCTAssertEqual(graphSelected.list.selectedRow?.id, Array(second.utf8))
        do {
            _ = try await session.selectAnimation("missing")
            XCTFail("Unknown identity must not replace selection")
        } catch { XCTAssertEqual(error as? DocumentAnimationError, .missingAnimation("missing")) }
        let retained = try await session.animationSnapshot()
        XCTAssertEqual(retained.list.selectedRow?.id, Array(second.utf8))
        let cleared = try await session.selectAnimation(nil)
        XCTAssertNil(cleared.list.selectedRow)
        XCTAssertEqual(cleared.editor.selectedID, "node")
        _ = try await session.selectAnimation(first)
        let reopened = try await session.open(data: document.encoded())
        let fresh = try await session.animationSnapshot()
        XCTAssertNotEqual(reopened.documentIdentity, opened.documentIdentity)
        XCTAssertNil(fresh.list.selectedRow)
    }

    func testOptionalCatalogFailureRetainsCauseWithoutBlockingGraphOpenEditsOrUndo() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='same'/><animation id='same'/></animations></canvas>".utf8))
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        let failed = try await session.animationSnapshot()
        XCTAssertTrue(failed.list.rows.isEmpty)
        XCTAssertEqual(failed.list.issue as? DocumentAnimationError, .duplicateIdentity("same"))
        do {
            _ = try await session.selectAnimation("same")
            XCTFail("Uninterpretable catalog must retain original cause")
        } catch { XCTAssertEqual(error as? DocumentAnimationError, .duplicateIdentity("same")) }
        let changed = try await session.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
        XCTAssertNotEqual(changed.document.encoded(), document.encoded())
        let cleared = try await session.selectAnimation(nil)
        XCTAssertEqual(cleared.list.issue as? DocumentAnimationError, .duplicateIdentity("same"))
        _ = try await session.undo()
        let restored = try await session.animationSnapshot()
        XCTAssertEqual(restored.editor.document.encoded(), document.encoded())
        XCTAssertEqual(restored.list.issue as? DocumentAnimationError, .duplicateIdentity("same"))
    }

    func testSelectedRecordEditsAndDeletionPublishMatchingRevisionAndPreserveHistory() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='Original' type='future' retained='keep'/></animations></canvas>"
                    .utf8))
        let session = EditorSession()
        _ = try await session.open(data: document.encoded())
        _ = try await session.selectAnimation("a")
        let edited = try await session.apply([
            .setAnimationName(id: "a", name: "Renamed"),
            .setAnimationType(id: "a", type: "other-future"),
            .setAnimationParameter(id: "a", name: "duration", value: "2.50"),
        ])
        let presentation = try await session.animationSnapshot()
        XCTAssertEqual(presentation.editor.documentRevision, edited.documentRevision)
        XCTAssertEqual(presentation.editor.document.encoded(), edited.document.encoded())
        XCTAssertEqual(presentation.list.selectedRow?.title, "Renamed")
        XCTAssertEqual(presentation.list.selectedRow?.typeLabel, "other-future")
        XCTAssertEqual(presentation.list.selectedRow?.source.parameter(named: "duration"), "2.50")
        XCTAssertEqual(presentation.list.selectedRow?.source.parameter(named: "retained"), "keep")
        _ = try await session.apply([.deleteAnimation(id: "a")])
        let deleted = try await session.animationSnapshot()
        XCTAssertTrue(deleted.list.rows.isEmpty)
        XCTAssertNil(deleted.list.selectedRow)
        _ = try await session.undo()
        let restored = try await session.animationSnapshot()
        XCTAssertEqual(restored.editor.document.encoded(), edited.document.encoded())
        XCTAssertNil(restored.list.selectedRow)
    }

    func testCanceledRequestsLeaveDocumentAndTransientSelectionUnchanged() async throws {
        let session = EditorSession()
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='A' type='future'/></animations></canvas>".utf8))
        _ = try await session.open(data: document.encoded())
        let original = try await session.selectAnimation("a")
        let operations: [@Sendable () async throws -> EditorAnimationSnapshot] = [
            { try await session.animationSnapshot() },
            { try await session.selectAnimation(nil) },
            { try await session.createAnimation(name: "New", type: "future") },
            { try await session.duplicateAnimation(id: "a", name: "Copy") },
        ]
        for operation in operations {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await operation()
            }
            do {
                _ = try await task.value
                XCTFail("Canceled request must not publish state")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        let unchanged = try await session.animationSnapshot()
        XCTAssertEqual(unchanged.editor.document.encoded(), original.editor.document.encoded())
        XCTAssertEqual(unchanged.editor.documentRevision, original.editor.documentRevision)
        XCTAssertEqual(unchanged.list.selectedRow?.source.id, "a")
    }

    func testUnloadedSessionAndEmptyPresentationAreDistinct() async throws {
        let session = EditorSession()
        do {
            _ = try await session.animationSnapshot()
            XCTFail("Unloaded session has no source-correlated list")
        } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        let unloadedOperations: [@Sendable () async throws -> EditorAnimationSnapshot] = [
            { try await session.selectAnimation("a") },
            { try await session.createAnimation(name: "New", type: "future") },
            { try await session.duplicateAnimation(id: "a", name: "Copy") },
        ]
        for operation in unloadedOperations {
            do {
                _ = try await operation()
                XCTFail("Unloaded request must reject")
            } catch { XCTAssertEqual(error as? EditorError, .notLoaded) }
        }
        _ = try await session.open(data: Dust3DDocument.emptyArchive())
        let empty = try await session.animationSnapshot()
        XCTAssertTrue(empty.list.rows.isEmpty)
        XCTAssertNil(empty.list.issue)
        XCTAssertNil(empty.list.selectedRow)
    }
}
