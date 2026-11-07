import Dust3DDocument
import Dust3DEditorModel
import XCTest

@MainActor
final class GraphPartMaterialTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
                <node id='c' partId='q' x='2' y='0' z='0' radius='.1'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b'/></edges>
                <parts><part id='p' metallic='.30' roughness='future' emissive='1.25' retained='yes'/>
                <part id='q' target='CutFace'/></parts>
                <components><component id='cp' linkDataType='partId' linkData='p'/>
                <component id='cq' linkDataType='partId' linkData='q'/></components></canvas>
                """.utf8))
    }

    func testGraphModelOwnerRequiresOnePartAcrossNodesAndEdges() throws {
        var state = try EditorState(document: source())
        try state.selectGraph(nodes: ["a"], edges: ["ab"])
        XCTAssertEqual(GraphModelPartTarget(snapshot: state.snapshot).part?.id, "p")
        try state.selectGraph(nodes: ["c"], edges: ["ab"])
        XCTAssertNil(GraphModelPartTarget(snapshot: state.snapshot).part)
        try state.select("c")
        XCTAssertNil(GraphModelPartTarget(snapshot: state.snapshot).part)
        try state.selectComponent("cp")
        XCTAssertNil(GraphModelPartTarget(snapshot: state.snapshot).part)
    }

    func testFieldDefaultsAndMaterialOnlyHistoryPreserveGraphAndExactUndo() async throws {
        let source = try source()
        let session = EditorSession()
        for property in PartMaterialProperty.allCases {
            _ = try await session.open(data: source.encoded())
            let before = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
            let changed = try await session.setGraphPartMaterial(
                property, value: property.defaultValue, target: GraphModelPartTarget(snapshot: before))
            let part = try XCTUnwrap(changed.parts.first { $0.id == "p" })
            XCTAssertEqual(part.materialValue(property), property.defaultValue)
            let previous = try XCTUnwrap(before.parts.first { $0.id == "p" })
            for other in PartMaterialProperty.allCases where other != property {
                XCTAssertEqual(part.materialValue(other), previous.materialValue(other))
            }
            let model = try XMLDocument(data: changed.document.modelXML)
            let element = try XCTUnwrap(try model.nodes(forXPath: "//part[@id='p']").first as? XMLElement)
            XCTAssertEqual(element.attribute(forName: "retained")?.stringValue, "yes")
            XCTAssertNil(element.attribute(forName: property.rawValue))
            XCTAssertEqual(changed.selectedIDs, ["a"])
            XCTAssertEqual(changed.selectedEdgeIDs, ["ab"])
            XCTAssertEqual(changed.previewIdentity.geometry, before.previewIdentity.geometry)
            XCTAssertNotEqual(changed.previewIdentity.materials, before.previewIdentity.materials)

            let noOp = try await session.setGraphPartMaterial(
                property, value: property.defaultValue, target: GraphModelPartTarget(snapshot: changed))
            XCTAssertEqual(noOp.document.encoded(), changed.document.encoded())
            XCTAssertEqual(noOp.documentRevision, changed.documentRevision)
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), source.encoded())
            XCTAssertFalse(undone.canUndo)
        }
    }

    func testActorRejectsSelectionRoundTripAndFailedReplacement() async throws {
        let source = try source()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let before = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        let stale = GraphModelPartTarget(snapshot: before)
        _ = try await session.select("c")
        let restored = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        try await assertRejected(session, target: stale)
        do {
            _ = try await session.open(data: Data("bad archive".utf8))
            XCTFail("Invalid replacement was accepted")
        } catch {}
        try await assertRejected(session, target: GraphModelPartTarget(snapshot: restored))
        let retained = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        XCTAssertEqual(retained.document.encoded(), source.encoded())
        XCTAssertFalse(retained.canUndo)
    }

    private func assertRejected(_ session: EditorSession, target: GraphModelPartTarget) async throws {
        do {
            _ = try await session.setGraphPartMaterial(.emissive, value: 2, target: target)
            XCTFail("Retired target was accepted")
        } catch {
            XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment)
        }
    }
}
