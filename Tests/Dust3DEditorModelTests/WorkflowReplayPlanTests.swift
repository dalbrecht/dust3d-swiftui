import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class WorkflowReplayPlanTests: XCTestCase {
    func testReplaySpeedUsesBoundedReferenceIntervals() {
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: 1), 2995)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: 11), 1445)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: 20), 50)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: .min), 2995)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: .max), 50)
    }


    func testReconstructsComponentOrderChainsAndLoopClosure() throws {
        let document = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <parts><part id="chain"/><part id="loop" rounded="true"/></parts>
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
                <component id="loopComponent" linkDataType="partId" linkData="loop" color="#ff0000"/>
                <component id="chainComponent" linkDataType="partId" linkData="chain"/>
              </components>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: document)
        XCTAssertEqual(Array(plan.steps.prefix(7)), [
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
        XCTAssertEqual(plan.steps.count, 9)
        let before = try plan.previewDocument(after: 7, source: document)
        XCTAssertFalse(String(decoding: before.modelXML, as: UTF8.self).contains("rounded="))
        XCTAssertFalse(String(decoding: before.modelXML, as: UTF8.self).contains("color="))
        let rounded = try plan.previewDocument(after: 8, source: document)
        XCTAssertTrue(String(decoding: rounded.modelXML, as: UTF8.self).contains("rounded=\"true\""))
        XCTAssertFalse(String(decoding: rounded.modelXML, as: UTF8.self).contains("color="))
        XCTAssertEqual(try plan.previewDocument(after: plan.steps.count, source: document).encoded(), document.encoded())

    }
}
