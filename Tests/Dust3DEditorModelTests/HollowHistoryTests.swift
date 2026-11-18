import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class HollowHistoryTests: XCTestCase {
    func testHollowEditAndRepeatedValueUseOneHistoryStep() async throws {
        let xml = "<canvas><parts><part id='p'/></parts></canvas>"
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let command = DocumentCommand.setPartHollowThickness(id: "p", thickness: 0.5)
        let changed = try await session.apply([command])
        _ = try await session.apply([command])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        let redone = try await session.redo()
        XCTAssertEqual(redone.document.encoded(), changed.document.encoded())
    }

    func testHollowEditRejectsReplacedDocumentWithTheSamePartID() async throws {
        let original = try Dust3DDocument(snapshotXML: Data("<canvas><parts><part id='p'/></parts></canvas>".utf8))
        let replacement = try original.applying(.setPartHollowThickness(id: "p", thickness: 0.25))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let originalSelection = try await session.selectPart("p")
        let retiredTarget = CanvasAdjustmentTarget(snapshot: originalSelection)

        _ = try await session.open(data: replacement.encoded())
        let replacementSelection = try await session.selectPart("p")
        XCTAssertEqual(originalSelection.documentRevision, replacementSelection.documentRevision)
        XCTAssertEqual(originalSelection.selectionRevision, replacementSelection.selectionRevision)
        XCTAssertNotEqual(originalSelection.documentIdentity, replacementSelection.documentIdentity)
        do {
            _ = try await session.setPartHollowThickness(id: "p", thickness: 1, target: retiredTarget)
            XCTFail("The old document target must reject the edit")
        } catch EditorError.stalePartGraphSelection {}
        let afterRejection = try await session.selectPart("p")
        XCTAssertEqual(afterRejection.document.encoded(), replacement.encoded())

        let currentTarget = CanvasAdjustmentTarget(snapshot: afterRejection)
        let edited = try await session.setPartHollowThickness(id: "p", thickness: 1, target: currentTarget)
        let expected = try replacement.applying(.setPartHollowThickness(id: "p", thickness: 1))
        XCTAssertEqual(edited.document.encoded(), expected.encoded())
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), replacement.encoded())
    }

    func testHollowEditRejectsStaleSelection() async throws {
        let original = try Dust3DDocument(snapshotXML: Data("<canvas><parts><part id='p'/></parts></canvas>".utf8))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectPart("p")
        let target = CanvasAdjustmentTarget(snapshot: selected)
        _ = try await session.selectPart(nil)
        do {
            _ = try await session.setPartHollowThickness(id: "p", thickness: 0.5, target: target)
            XCTFail("Stale selection must reject the edit")
        } catch EditorError.stalePartGraphSelection {}
    }
}
