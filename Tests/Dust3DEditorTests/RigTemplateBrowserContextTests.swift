import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

final class RigTemplateBrowserContextTests: XCTestCase {
    func testCountsRetainAllStoredEdgesButAssignmentRequiresExplicitSelectionAndExactTemplate() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Biped'><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e' partId='p' from='a' to='b' boneName='Root'/><edge id='f' partId='p' from='b' to='a' boneName='root'/></edges><parts><part id='p'/></parts></canvas>"
                    .utf8))
        var state = try EditorState(document: document)
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let unselected = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: state.snapshot)
        XCTAssertEqual(unselected.assignmentCount("Root"), 1)
        XCTAssertEqual(unselected.assignmentCount("root"), 1)
        XCTAssertEqual(unselected.assignmentCount("Hips"), 0)
        XCTAssertTrue(unselected.isCurrent(in: state.snapshot))
        XCTAssertTrue(unselected.contains("Root"))
        XCTAssertFalse(unselected.contains("root"))
        XCTAssertFalse(unselected.assignment.isAvailable)
        try state.selectGraph(nodes: [], edges: ["e"])
        XCTAssertFalse(unselected.isCurrent(in: state.snapshot))
        let selected = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: state.snapshot)
        XCTAssertTrue(selected.assignment.isAvailable)
        let other = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Bird"))
        XCTAssertFalse(
            RigTemplateBrowserContext(hierarchy: other, snapshot: state.snapshot).isCurrent(in: state.snapshot))
        try state.selectGraph(nodes: [], edges: [])
        try state.selectGraph(nodes: [], edges: ["e"])
        XCTAssertFalse(selected.isCurrent(in: state.snapshot))
        let anotherWindow = try EditorState(document: document)
        XCTAssertFalse(unselected.isCurrent(in: anotherWindow.snapshot))
    }
    func testClearTargetsUseChosenBoneAndExactDescendantsAcrossReadonlyParts() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Biped'><nodes><node id='a' partId='p' x='.1' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.2' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='e1' partId='p' from='a' to='b' boneName='Head'/><edge id='e2' partId='unknown' from='b' to='a' boneName='HairBack3'/><edge id='e3' from='a' to='b' boneName='LeftUpperArm'/><edge id='e4' from='b' to='a' boneName='head'/></edges><parts><part id='p' locked='true'/></parts></canvas>"
                    .utf8))
        let state = try EditorState(document: document)
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let context = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: state.snapshot)
        XCTAssertEqual(context.clearTarget(name: "Head", includeDescendants: false)?.matchingEdgeCount, 1)
        let chain = try XCTUnwrap(context.clearTarget(name: "Head", includeDescendants: true))
        XCTAssertEqual(chain.matchingEdgeCount, 2)
        XCTAssertTrue(chain.isCurrent(in: state.snapshot))
        XCTAssertNil(context.clearTarget(name: "head", includeDescendants: true))
        let bird = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Bird"))
        XCTAssertNil(
            RigTemplateBrowserContext(hierarchy: bird, snapshot: state.snapshot).clearTarget(
                name: "Head", includeDescendants: true))
        XCTAssertEqual(context.clearTarget(name: "Root", includeDescendants: true)?.matchingEdgeCount, 3)
    }

}
