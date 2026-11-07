import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor
final class GraphLoopInteriorTests: XCTestCase {
    private func source(
        role: String = "StitchingLoop",
        links: String = "<component id='loop' linkDataType='partId' linkData='p'/>"
    ) throws -> Data {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
                <node id='c' partId='q' x='2' y='0' z='0' radius='.1'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b'/></edges>
                <parts><part id='p' target='\(role)' fillLoopInterior='future' locked='true' extra='keep'/>
                <part id='q' target='StitchingLoop' fillLoopInterior='true'/></parts>
                <components>\(links)<component id='other' linkDataType='partId' linkData='q'/></components>
                </canvas>
                """.utf8)
        ).encoded()
    }

    func testCapturedLoopEditPreservesPicksAndOneExactUndo() async throws {
        let original = try source()
        for value in [false, true] {
            let session = EditorSession()
            _ = try await session.open(data: original)
            let selected = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
            let target = GraphLoopInteriorTarget(snapshot: selected)
            XCTAssertEqual(target.part?.id, "p")
            XCTAssertNil(target.part?.isLoopInteriorFilled)
            let changed = try await session.setGraphLoopInterior(value, target: target)
            XCTAssertEqual(changed.parts.first { $0.id == "p" }?.isLoopInteriorFilled, value)
            XCTAssertEqual(changed.parts.first { $0.id == "p" }?.isLocked, true)
            XCTAssertEqual(changed.parts.first { $0.id == "q" }?.isLoopInteriorFilled, true)
            XCTAssertEqual(changed.selectedIDs, selected.selectedIDs)
            XCTAssertEqual(changed.selectedEdgeIDs, selected.selectedEdgeIDs)
            XCTAssertNotEqual(changed.previewIdentity, selected.previewIdentity)
            let same = try await session.setGraphLoopInterior(value, target: .init(snapshot: changed))
            XCTAssertEqual(same.documentRevision, changed.documentRevision)
            XCTAssertEqual(same.document.encoded(), changed.document.encoded())
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), original)
            XCTAssertFalse(undone.canUndo)
        }
    }

    func testOnlySoleExactLinkedStitchingLoopIsEligible() throws {
        for original in [
            try source(role: "StitchingLine"), try source(links: ""),
            try source(links: "<component id='loop' linkDataType='partId' linkData='P'/>"),
            try source(
                links: """
                    <component id='one' linkDataType='partId' linkData='p'/>
                    <component id='two' linkDataType='partId' linkData='p'/>
                    """),
        ] {
            var state = try EditorState(document: Dust3DDocument(data: original))
            try state.selectGraph(nodes: [], edges: ["ab"])
            XCTAssertNil(GraphLoopInteriorTarget(snapshot: state.snapshot).part)
        }
        var state = try EditorState(document: Dust3DDocument(data: source()))
        try state.selectGraph(nodes: [], edges: ["ab"])
        XCTAssertEqual(GraphLoopInteriorTarget(snapshot: state.snapshot).part?.id, "p")
        try state.selectGraph(nodes: ["c"], edges: ["ab"])
        XCTAssertNil(GraphLoopInteriorTarget(snapshot: state.snapshot).part)
    }

    func testRetainedTargetCannotCrossSelectionABAOrFailedReplacement() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original)
        let initial = try await session.selectGraph(nodes: [], edges: ["ab"])
        let stale = GraphLoopInteriorTarget(snapshot: initial)
        _ = try await session.select("c")
        let current = try await session.selectGraph(nodes: [], edges: ["ab"])
        do {
            _ = try await session.setGraphLoopInterior(true, target: stale)
            XCTFail("Selection ABA retained the loop target")
        } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }
        let fresh = GraphLoopInteriorTarget(snapshot: current)
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid replacement opened")
        } catch {}
        do {
            _ = try await session.setGraphLoopInterior(true, target: fresh)
            XCTFail("Failed replacement retained a writable loop target")
        } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }
        let retained = try await session.animationSnapshot().editor
        XCTAssertEqual(retained.document.encoded(), original)
        XCTAssertFalse(retained.canUndo)
    }
}
