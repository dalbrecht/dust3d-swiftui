import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PartTargetPreviewTests: XCTestCase {
    func testProfileOnlyDocumentsHaveNoJoinedPreviewButKeepTheirEditableNodes() throws {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
            .applying(.addNode(id: "a", partID: "p", componentID: "cp", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
            .applying(.addNode(id: "b", partID: "q", componentID: "cq", position: .init(x: 1, y: 0, z: 0), radius: 0.1))
        var state = try EditorState(document: document)
        let nodes = state.snapshot.nodes
        try state.apply([.setPartTarget(id: "p", target: .cutFace)])
        XCTAssertTrue(state.snapshot.hasEnabledGeometry)
        try state.apply([.setPartTarget(id: "q", target: .cutFace)])
        XCTAssertFalse(state.snapshot.hasEnabledGeometry)
        XCTAssertEqual(state.snapshot.nodes, nodes)
        for target in [PartTarget.model, .stitchingLine, .stitchingLoop] {
            try state.apply([.setPartTarget(id: "p", target: target)])
            XCTAssertTrue(state.snapshot.hasEnabledGeometry)
            try state.apply([.setPartState(id: "p", property: .disabled, value: true)])
            XCTAssertFalse(state.snapshot.hasEnabledGeometry)
            try state.apply([.setPartState(id: "p", property: .disabled, value: false)])
            XCTAssertTrue(state.snapshot.hasEnabledGeometry)
        }
    }
}
