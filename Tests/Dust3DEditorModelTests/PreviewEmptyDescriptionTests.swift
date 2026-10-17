import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PreviewEmptyDescriptionTests: XCTestCase {
    func testLoadedEmptyDocumentOffersNodeCreationInsteadOfOpenPrompt() throws {
        let state = try EditorState(document: Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        XCTAssertEqual(state.snapshot.previewEmptyDescription, "Add nodes to begin modeling.")
    }
    func testDisabledAndProfileOnlyDocumentsExplainMissingMeshContributors() throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "n", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        for command in [
            DocumentCommand.setPartTarget(id: "p", target: .cutFace),
            .setPartState(id: "p", property: .disabled, value: true),
        ] {
            let state = try EditorState(document: source.applying(command))
            XCTAssertEqual(
                state.snapshot.previewEmptyDescription, "Enable a model or stitching part to generate the mesh.")
        }
    }
    func testLoadedMeshEligibleDocumentExplainsSuccessfulEmptyOutput() throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "n", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let state = try EditorState(document: source)
        XCTAssertEqual(state.snapshot.previewEmptyDescription, "The current document generates no mesh geometry.")
    }
}
