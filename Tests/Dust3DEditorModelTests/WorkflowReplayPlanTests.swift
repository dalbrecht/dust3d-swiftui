import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class WorkflowReplayPlanTests: XCTestCase {
    func testReconstructsComponentOrderChainsAndLoopClosure() throws {
        let document = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <parts><part id="chain"/><part id="loop"/></parts>
              <nodes>
                <node id="middle" partId="chain" x="0" y="0" z="0" radius=".1"/>
                <node id="start" partId="chain" x="0" y="1" z="0" radius=".1"/>
                <node id="end" partId="chain" x="0" y="2" z="0" radius=".1"/>
                <node id="a" partId="loop" x="1" y="0" z="0" radius=".1"/>
                <node id="b" partId="loop" x="1" y="1" z="0" radius=".1"/>
                <node id="c" partId="loop" x="1" y="2" z="0" radius=".1"/>
              </nodes>
              <edges>
                <edge id="backward" partId="chain" from="middle" to="start"/>
                <edge id="forward" partId="chain" from="middle" to="end"/>
                <edge id="ab" partId="loop" from="a" to="b"/>
                <edge id="bc" partId="loop" from="b" to="c"/>
                <edge id="ca" partId="loop" from="c" to="a"/>
              </edges>
              <components>
                <component id="loopComponent" linkDataType="partId" linkData="loop"/>
                <component id="chainComponent" linkDataType="partId" linkData="chain"/>
              </components>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: document)
        XCTAssertEqual(plan.steps, [
            .node(id: "a", incomingEdgeID: nil), .node(id: "b", incomingEdgeID: "ab"),
            .node(id: "c", incomingEdgeID: "bc"), .edge(id: "ca"),
            .node(id: "start", incomingEdgeID: nil), .node(id: "middle", incomingEdgeID: "backward"),
            .node(id: "end", incomingEdgeID: "forward"),
        ])
        XCTAssertTrue(plan.frame(after: -1).nodes.isEmpty)
        let partial = plan.frame(after: 3)
        XCTAssertEqual(partial.nodes.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(partial.edges.map(\.id), ["ab", "bc"])
        let final = plan.frame(after: plan.steps.count + 1)
        XCTAssertEqual(final.nodes, try document.editorContents().nodes)
        XCTAssertEqual(final.edges, try document.editorContents().edges)
        XCTAssertEqual(final.edges.first?.fromID, "middle")
        let partialArchive = try plan.previewDocument(after: 3, source: document)
        let partialGraph = try partialArchive.editorContents()
        XCTAssertEqual(partialGraph.nodes.map(\.id), partial.nodes.map(\.id))
        XCTAssertEqual(partialGraph.nodes.map(\.value), partial.nodes.map(\.value))
        XCTAssertEqual(partialGraph.edges, partial.edges)
        XCTAssertEqual(partialGraph.parts.map(\.id), ["loop"])
        XCTAssertEqual(try partialArchive.components().map(\.id), ["loopComponent"])
        XCTAssertEqual(try plan.previewDocument(after: plan.steps.count, source: document).encoded(), document.encoded())

    }
}
