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
