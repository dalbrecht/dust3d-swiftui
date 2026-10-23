import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class RigParameterSessionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='future' headHasEyelids='False' future='keep'><nodes><node id='node' partId='part' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='part'/></parts><components><component id='component' linkDataType='partId' linkData='part'/></components></canvas>"
                    .utf8))
    }

    func testRigBatchPublishesCachedIntentWithOneUndoAndRetainsInteractionState() async throws {
        let source = try document()
        let session = EditorSession()
        let opened = try await session.open(data: source.encoded())
        XCTAssertNil(opened.rigSettings.rigType)
        XCTAssertEqual(opened.rigSettings.sourceRigType, "future")
        _ = try await session.select("node")
        _ = try await session.setLock(.radius, isLocked: true)
        let changed = try await session.apply([.setRigType(.bird), .setHeadHasEyelids(true)])
        XCTAssertEqual(changed.rigSettings.rigType, .bird)
        XCTAssertTrue(changed.rigSettings.headHasEyelids)
        XCTAssertEqual(changed.rigSettings, try changed.document.rigSettings())
        XCTAssertEqual(changed.selectedIDs, ["node"])
        XCTAssertEqual(changed.locks, [.radius])
        XCTAssertEqual(changed.documentIdentity, opened.documentIdentity)
        XCTAssertEqual(changed.nodes, opened.nodes)
        XCTAssertEqual(changed.documentRevision, 1)
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertEqual(undone.rigSettings, opened.rigSettings)
        XCTAssertFalse(undone.canUndo)
        XCTAssertTrue(undone.canRedo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
        XCTAssertEqual(redone.rigSettings, changed.rigSettings)
        let noop = try await session.apply([.setRigType(.bird), .setHeadHasEyelids(true)])
        XCTAssertEqual(noop.documentRevision, redone.documentRevision)
        _ = try await session.undo()
        let preservedRedo = try await session.apply([.setHeadHasEyelids(false)])
        XCTAssertTrue(preservedRedo.canRedo)
        XCTAssertEqual(preservedRedo.document.encoded(), source.encoded())
    }

    func testFailedBatchDoesNotPublishRigIntentOrReplaceRedo() async throws {
        let session = EditorSession()
        let source = try document()
        let opened = try await session.open(data: source.encoded())
        _ = try await session.apply([.setRigType(.fish)])
        _ = try await session.undo()
        do {
            _ = try await session.apply([
                .setRigType(.spider), .setHeadHasEyelids(true),
                .setNode(id: "missing", position: .init(x: 0, y: 0, z: 0), radius: 0.1),
            ])
            XCTFail("Reject the entire batch")
        } catch {
            XCTAssertEqual(error as? DocumentError, .missingNode("missing"))
        }
        let current = try await session.select("node")
        XCTAssertEqual(current.document.encoded(), source.encoded())
        XCTAssertEqual(current.rigSettings, opened.rigSettings)
        XCTAssertTrue(current.canRedo)
        let redone = try await session.redo()
        XCTAssertEqual(redone.rigSettings.rigType, .fish)
        XCTAssertFalse(redone.rigSettings.headHasEyelids)
    }

    func testIndependentSessionsAndReplacementDoNotLeakRigIntent() async throws {
        let first = EditorSession()
        let second = EditorSession()
        let source = try document()
        let firstOpened = try await first.open(data: source.encoded())
        _ = try await second.open(data: source.encoded())
        _ = try await first.apply([.setRigType(.snake), .setHeadHasEyelids(true)])
        let untouched = try await second.select("node")
        XCTAssertEqual(untouched.rigSettings, firstOpened.rigSettings)
        XCTAssertFalse(untouched.canUndo)
        let replacement = try await first.open(data: Dust3DDocument.emptyArchive())
        XCTAssertEqual(replacement.rigSettings.rigType, .disabled)
        XCTAssertNil(replacement.rigSettings.sourceRigType)
        XCTAssertFalse(replacement.rigSettings.headHasEyelids)
        XCTAssertNotEqual(replacement.documentIdentity, firstOpened.documentIdentity)
        XCTAssertFalse(replacement.canUndo)
    }
}
