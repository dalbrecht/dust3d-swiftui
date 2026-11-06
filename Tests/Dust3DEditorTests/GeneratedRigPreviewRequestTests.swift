import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class GeneratedRigPreviewRequestTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Snake'><nodes><node id='n' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='p'/></parts></canvas>"
                    .utf8))
    }
    func testRigOnlyEditAndUndoRejectOldRequestEvenWhenGeometryOrBytesMatch() async throws {
        let session = EditorSession()
        let opened = try await session.open(data: document().encoded())
        let request = GeneratedRigPreviewRequest(snapshot: opened)
        XCTAssertTrue(request.matches(opened))
        let changed = try await session.apply([.setHeadHasEyelids(true)])
        XCTAssertEqual(changed.previewIdentity.geometry, opened.previewIdentity.geometry)
        XCTAssertFalse(request.matches(changed))
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), opened.document.encoded())
        XCTAssertFalse(request.matches(restored))
    }
    func testOtherDocumentRejectsSameBytesAndSelectionDoesNotRegenerate() async throws {
        let session = EditorSession()
        let bytes = try document().encoded()
        let opened = try await session.open(data: bytes)
        let request = GeneratedRigPreviewRequest(snapshot: opened)
        let selected = try await session.select("n")
        XCTAssertTrue(request.matches(selected))
        let other = try await EditorSession().open(data: bytes)
        XCTAssertFalse(request.matches(other))
        XCTAssertEqual(Set([request, GeneratedRigPreviewRequest(snapshot: opened)]).count, 1)
    }
}
