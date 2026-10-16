import Dust3DDocument
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class ReferenceCompositionPresentationTests: XCTestCase {
    func testPresentationAlwaysCarriesTheCapturedTargetAndReopeningCreatesFreshIdentity() throws {
        var state = try EditorState(document: Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        let first = ReferenceCompositionPresentation(snapshot: state.snapshot)
        let reopened = ReferenceCompositionPresentation(snapshot: state.snapshot)
        XCTAssertNotEqual(first.id, reopened.id)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 1])
        try state.applyReferenceComposition(png: png, origin: nil, target: first.target)
        XCTAssertEqual(state.snapshot.document.referenceImagePNG, png)
        XCTAssertThrowsError(try state.applyReferenceComposition(png: png, origin: nil, target: reopened.target))
    }
}
