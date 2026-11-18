import Dust3DDocument
import Dust3DEditorModel
import XCTest

@MainActor
final class GraphPartRoleTests: XCTestCase {
    private let profileID = "{00000000-0000-4000-8000-000000000001}"

    private func source(
        role: String = "CutFace", duplicateOwner: Bool = false, ownerless: Bool = false
    ) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='\(profileID)' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='\(profileID)' x='1' y='0' z='0' radius='.1'/>
                <node id='c' partId='q' x='2' y='0' z='0' radius='.1'/>
                </nodes><edges><edge id='ab' partId='\(profileID)' from='a' to='b'/></edges>
                <parts><part id='\(profileID)' target='\(role)' locked='true' future='retain'/>
                <part id='q' cutFace='\(profileID)'/></parts><components>
                \(ownerless ? "" : "<component id='cp' linkDataType='partId' linkData='\(profileID)'/>")
                <component id='cq' linkDataType='partId' linkData='q'/>
                \(duplicateOwner ? "<component id='other' linkDataType='partId' linkData='\(profileID)'/>" : "")
                </components></canvas>
                """.utf8))
    }

    func testRoleTargetRequiresOneUniqueLinkedGraphOwner() throws {
        for original in [try source(duplicateOwner: true), try source(ownerless: true)] {
            var state = try EditorState(document: original)
            try state.selectGraph(nodes: ["a"], edges: ["ab"])
            XCTAssertNil(GraphPartRoleTarget(snapshot: state.snapshot).part)
        }
        var state = try EditorState(document: source())
        try state.selectGraph(nodes: ["c"], edges: ["ab"])
        XCTAssertNil(GraphPartRoleTarget(snapshot: state.snapshot).part)
        try state.selectComponent("cp")
        XCTAssertNil(GraphPartRoleTarget(snapshot: state.snapshot).part)
        try state.selectEdges(["ab"])
        XCTAssertEqual(GraphPartRoleTarget(snapshot: state.snapshot).part?.target, .cutFace)
    }

    func testExistingCutFaceAndStitchingRolesCanReturnToModelWithExactUndo() async throws {
        let session = EditorSession()
        for role in [PartTarget.cutFace, .stitchingLine, .stitchingLoop] {
            let original = try source(role: role.rawValue)
            _ = try await session.open(data: original.encoded())
            let before = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
            let target = GraphPartRoleTarget(snapshot: before)
            XCTAssertEqual(target.part?.target, role)
            XCTAssertEqual(target.part?.cutFaceReferenceCount, role == .cutFace ? 1 : 0)
            let same = try await session.setGraphPartRole(role, target: target)
            XCTAssertEqual(same.document.encoded(), original.encoded())
            XCTAssertFalse(same.canUndo)
            let changed = try await session.setGraphPartRole(.model, target: target)
            XCTAssertEqual(changed.selectedIDs, ["a"])
            XCTAssertEqual(changed.selectedEdgeIDs, ["ab"])
            XCTAssertEqual(GraphPartRoleTarget(snapshot: changed).part?.target, .model)
            XCTAssertEqual(GraphPartRoleTarget(snapshot: changed).part?.isLocked, true)
            let xml = try XMLDocument(data: changed.document.modelXML)
            let part = try XCTUnwrap(try xml.nodes(forXPath: "//part[@id='\(profileID)']").first as? XMLElement)
            XCTAssertNil(part.attribute(forName: "target"))
            XCTAssertEqual(part.attribute(forName: "future")?.stringValue, "retain")
            let consumer = try XCTUnwrap(try xml.nodes(forXPath: "//part[@id='q']").first as? XMLElement)
            XCTAssertEqual(consumer.attribute(forName: "cutFace")?.stringValue, profileID)
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), original.encoded())
            XCTAssertFalse(undone.canUndo)
        }
    }

    func testRoleActorRejectsSelectionRoundTripAndFailedSource() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        _ = try await session.select("c")
        let restored = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        await assertRejected(session, target: GraphPartRoleTarget(snapshot: before))
        do {
            _ = try await session.open(data: Data("bad archive".utf8))
            XCTFail("Invalid replacement was accepted")
        } catch {}
        await assertRejected(session, target: GraphPartRoleTarget(snapshot: restored))
        let retained = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        XCTAssertEqual(retained.document.encoded(), original.encoded())
        XCTAssertFalse(retained.canUndo)
    }

    private func assertRejected(_ session: EditorSession, target: GraphPartRoleTarget) async {
        do {
            _ = try await session.setGraphPartRole(.model, target: target)
            XCTFail("Retired target was accepted")
        } catch {
            XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment)
        }
    }
}
