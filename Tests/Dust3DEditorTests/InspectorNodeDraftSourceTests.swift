import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class InspectorNodeDraftSourceTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='.25' y='.5' z='.75' radius='.125'/>
                <node id='b' partId='p' x='.25' y='.5' z='.75' radius='.125'/>
                </nodes><parts><part id='p'/></parts></canvas>
                """.utf8))
    }

    func testTaperMetadataDoesNotChangeNumericDraftSourceButGeometryDoes() throws {
        var state = try EditorState(document: document())
        try state.select("a")
        let original = try XCTUnwrap(InspectorNodeDraftSource(state.snapshot))
        try state.apply([.setNodeDeformationScale(id: "a", property: .width, value: 1.5)])
        XCTAssertEqual(state.snapshot.selectedNode?.deformationScale(.width), 1.5)
        XCTAssertEqual(InspectorNodeDraftSource(state.snapshot), original)
        try state.apply([.setNode(id: "a", position: .init(x: 0.5, y: 0.5, z: 0.75), radius: 0.125)])
        XCTAssertNotEqual(InspectorNodeDraftSource(state.snapshot), original)
        try state.undo()
        XCTAssertEqual(InspectorNodeDraftSource(state.snapshot), original)
        try state.apply([.setNode(id: "a", position: .init(x: 0.25, y: 0.5, z: 0.75), radius: 0.25)])
        XCTAssertNotEqual(InspectorNodeDraftSource(state.snapshot), original)
    }

    func testSelectionRoundTripAndReplacementRetireIdenticalGeometry() throws {
        let document = try document()
        var state = try EditorState(document: document)
        XCTAssertNil(InspectorNodeDraftSource(state.snapshot))
        try state.select("a")
        let original = try XCTUnwrap(InspectorNodeDraftSource(state.snapshot))
        try state.select("a")
        XCTAssertEqual(InspectorNodeDraftSource(state.snapshot), original)
        try state.select("b")
        XCTAssertNotEqual(InspectorNodeDraftSource(state.snapshot), original)
        try state.select("a")
        XCTAssertNotEqual(InspectorNodeDraftSource(state.snapshot), original)

        var replacement = try EditorState(document: document)
        try replacement.select("a")
        XCTAssertNotEqual(InspectorNodeDraftSource(replacement.snapshot), original)
    }
}
