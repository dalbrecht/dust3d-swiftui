import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class WorkflowReplayPlanTests: XCTestCase {
    func testReferenceOnlyReplayAppliesImageBeforeGraphAndPreservesBytes() throws {
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
            .applying(.setReferenceImagePNG(png))
        let plan = try WorkflowReplayPlan(document: original)
        XCTAssertEqual(plan.steps, [.referenceImage])
        XCTAssertFalse(plan.showsReferenceImage(after: 0))
        XCTAssertTrue(plan.showsReferenceImage(after: 1))
        XCTAssertNil(try plan.previewDocument(after: 0, source: original).referenceImagePNG)
        XCTAssertEqual(try plan.previewDocument(after: 1, source: original).encoded(), original.encoded())
    }


    func testReplayBuildsGroupsAndMovesPartsAfterDrawing() throws {
        let source = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <parts><part id="p"/></parts>
              <nodes><node id="n" partId="p" x="0" y="0" z="0" radius=".1"/></nodes>
              <components>
                <component id="outer" name="Outer" color="#ff0000" xmlns:asset="urn:dust3d:test">
                  <component id="inner" name="Inner">
                    <component id="leaf" linkDataType="partId" linkData="p" asset:hint="keep"/>
                  </component>
                </component>
                <component id="empty" name="Empty Group"/>
              </components>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        XCTAssertEqual(plan.steps.count, 6)
        func components(after step: Int) throws -> [DocumentComponent] {
            try plan.previewDocument(after: step, source: source).components()
        }
        let drawn = try components(after: 1)
        XCTAssertEqual(drawn.map(\.id), ["leaf"])
        XCTAssertNil(drawn.first?.parentID)
        let drawing = try plan.previewDocument(after: 1, source: source)
        let xml = String(decoding: drawing.modelXML, as: UTF8.self)
        XCTAssertTrue(xml.contains("xmlns:asset=\"urn:dust3d:test\"") || xml.contains("xmlns:asset='urn:dust3d:test'"), xml)
        XCTAssertTrue(xml.contains("asset:hint=\"keep\""))
        let outerCreated = try components(after: 2)
        XCTAssertEqual(Set(outerCreated.map(\.id)), ["leaf", "outer"])
        XCTAssertEqual(outerCreated.first { $0.id == "outer" }?.color, .some(.unset))
        XCTAssertEqual(try components(after: 3).first { $0.id == "outer" }?.color,
                       try source.components().first?.color)
        let innerCreated = try components(after: 4)
        XCTAssertEqual(innerCreated.first { $0.id == "inner" }?.parentID, "outer")
        XCTAssertNil(innerCreated.first { $0.id == "leaf" }?.parentID)
        XCTAssertEqual(try components(after: 5).first { $0.id == "leaf" }?.parentID, "inner")
        XCTAssertFalse(try components(after: 5).contains { $0.id == "empty" })
        XCTAssertEqual(try plan.previewDocument(after: 6, source: source).encoded(), source.encoded())
    }

    func testLinkedCutFaceAppearsWhenItsProfileFinishes() throws {
        let profile = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let source = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <parts>
                <part id="tube" cutFace="\(profile)"/>
                <part id="\(profile)" target="CutFace" rounded="true"/>
                <part id="next"/>
              </parts>
              <nodes>
                <node id="tubeNode" partId="tube" x="0" y="0" z="0" radius=".1"/>
                <node id="profileNode" partId="\(profile)" x="1" y="0" z="0" radius=".1"/>
                <node id="nextNode" partId="next" x="2" y="0" z="0" radius=".1"/>
              </nodes>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        let drawn = try plan.previewDocument(after: 2, source: source).editorContents()
        XCTAssertEqual(drawn.parts.first { $0.id == profile }?.target, .model)
        let targeted = try plan.previewDocument(after: 3, source: source).editorContents()
        XCTAssertEqual(targeted.parts.first { $0.id == profile }?.target, .cutFace)
        let targetedXML = try plan.previewDocument(after: 3, source: source).modelXML
        XCTAssertFalse(String(decoding: targetedXML, as: UTF8.self).contains("rounded="))
        let beforeLink = try plan.previewDocument(after: 4, source: source).editorContents()
        XCTAssertEqual(beforeLink.parts.first { $0.id == "tube" }?.cutFace, .preset(.quad))
        let linked = try plan.previewDocument(after: 5, source: source).editorContents()
        XCTAssertEqual(linked.parts.first { $0.id == "tube" }?.cutFace, .linkedPart(profile))
        XCTAssertEqual(linked.nodes.map(\.id), ["tubeNode", "profileNode"])
        XCTAssertEqual(plan.steps.last, .node(id: "nextNode", incomingEdgeID: nil))
    }

    func testReplayStagesNodeCutFacesAndWaitsForLinkedProfiles() throws {
        let profile = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let source = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <parts><part id="tube"/><part id="\(profile)" target="CutFace"/><part id="next"/></parts>
              <nodes>
                <node id="a" partId="tube" x="0" y="0" z="0" radius=".1" cutFace="Triangle"/>
                <node id="b" partId="tube" x="0" y="1" z="0" radius=".1" cutFace="\(profile)" cutRotation=".25"/>
                <node id="p" partId="\(profile)" x="1" y="0" z="0" radius=".1"/>
                <node id="n" partId="next" x="2" y="0" z="0" radius=".1"/>
              </nodes>
              <edges><edge id="ab" partId="tube" from="a" to="b"/></edges>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        XCTAssertEqual(plan.steps.count, 8)
        func xml(after step: Int) throws -> String {
            String(decoding: try plan.previewDocument(after: step, source: source).modelXML, as: UTF8.self)
        }
        XCTAssertFalse(try xml(after: 2).contains("cutFace="))
        XCTAssertFalse(try xml(after: 2).contains("cutRotation="))
        XCTAssertTrue(try xml(after: 3).contains("cutFace=\"Triangle\""))
        XCTAssertTrue(try xml(after: 4).contains("cutRotation=\".25\""))
        XCTAssertFalse(try xml(after: 5).contains("cutFace=\"\(profile)\""))
        XCTAssertTrue(try xml(after: 7).contains("cutFace=\"\(profile)\""))
        XCTAssertEqual(plan.frame(after: 7).nodes.map(\.id), ["a", "b", "p"])
        XCTAssertEqual(try plan.previewDocument(after: 8, source: source).encoded(), source.encoded())
    }

    func testReplayStagesStitchingAndImportedTargets() throws {
        for target in ["StitchingLine", "StitchingLoop", "ImportedModel"] {
            let source = try Dust3DDocument(snapshotXML: Data("""
                <canvas>
                  <parts><part id="p" target="\(target)" importedModelId="retained"/></parts>
                  <nodes><node id="n" partId="p" x="0" y="0" z="0" radius=".1"/></nodes>
                  <components><component id="after"/></components>
                </canvas>
                """.utf8))
            let plan = try WorkflowReplayPlan(document: source)
            XCTAssertEqual(plan.steps.count, 3)
            let before = try plan.previewDocument(after: 1, source: source)
            XCTAssertEqual(try before.editorContents().parts.first?.target, .model)
            let after = try plan.previewDocument(after: 2, source: source)
            let xml = String(decoding: after.modelXML, as: UTF8.self)
            XCTAssertTrue(xml.contains("target=\"\(target)\""))
            XCTAssertTrue(xml.contains("importedModelId=\"retained\""))
            XCTAssertEqual(try plan.previewDocument(after: 3, source: source).encoded(), source.encoded())
        }
    }

    func testReplayAppliesGroupWrappingAsOneStep() throws {
        let source = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <components>
                <component id="body"/>
                <component id="cloth" name="Cloth" wrap="Cloth" wrapOffset=".025"
                    wrapBindTo="body" wrapFuture="retained"/>
                <component id="after"/>
              </components>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        XCTAssertEqual(plan.steps.count, 4)
        let before = try plan.previewDocument(after: 2, source: source)
        XCTAssertEqual(try before.components().last?.wrapping.mode, .some(.none))
        XCTAssertFalse(String(decoding: before.modelXML, as: UTF8.self).contains("wrap"))
        let after = try plan.previewDocument(after: 3, source: source)
        let cloth = try XCTUnwrap(try after.components().last)
        XCTAssertEqual(cloth.id, "cloth")
        XCTAssertEqual(cloth.wrapping.mode, .cloth)
        XCTAssertEqual(cloth.wrapping.scalarValue(.offset), 0.025)
        XCTAssertEqual(cloth.wrapping.binding, .stored("body"))
        XCTAssertTrue(String(decoding: after.modelXML, as: UTF8.self).contains("wrapFuture=\"retained\""))
        XCTAssertEqual(try plan.previewDocument(after: 4, source: source).encoded(), source.encoded())
    }

    func testReplayStagesRigBeforeByteDistinctBoneAssignments() throws {
        let firstName = "Cafe\u{301}"
        let secondName = "Caf\u{e9}"
        let source = try Dust3DDocument(snapshotXML: Data("""
            <canvas rigType="Biped">
              <parts><part id="p"/></parts>
              <nodes>
                <node id="a" partId="p" x="0" y="0" z="0" radius=".1"/>
                <node id="b" partId="p" x="0" y="1" z="0" radius=".1"/>
                <node id="c" partId="p" x="0" y="2" z="0" radius=".1"/>
              </nodes>
              <edges>
                <edge id="ab" from="a" to="b" boneName="\(firstName)"/>
                <edge id="bc" from="b" to="c" boneName="\(secondName)"/>
              </edges>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        XCTAssertEqual(plan.steps.count, 6)
        let drawn = try plan.previewDocument(after: 3, source: source).editorContents()
        XCTAssertEqual(drawn.rigSettings.rigType, .disabled)
        XCTAssertEqual(drawn.edges.map(\.boneName), ["", ""])
        let rigged = try plan.previewDocument(after: 4, source: source).editorContents()
        XCTAssertEqual(rigged.rigSettings.rigType, .biped)
        XCTAssertEqual(rigged.edges.map(\.boneName), ["", ""])
        let partiallyBound = try plan.previewDocument(after: 5, source: source).editorContents()
        XCTAssertTrue(partiallyBound.edges.first?.hasExactBoneName(firstName) == true)
        XCTAssertEqual(partiallyBound.edges.last?.boneName, "")
        XCTAssertEqual(plan.frame(after: 5).edges, partiallyBound.edges)
        XCTAssertEqual(try plan.previewDocument(after: 6, source: source).encoded(), source.encoded())
    }

    func testReplayRevealsStoredAnimationsAndParametersInOrder() throws {
        let source = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <parts><part id="p"/></parts>
              <nodes><node id="n" partId="p" x="0" y="0" z="0" radius=".1"/></nodes>
              <animations>
                <animation id="walk" name="Walk" type="Walk" speed=".5" duration="2"/>
                <animation id="jump" name="Jump" type="Jump"/>
              </animations>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        XCTAssertEqual(plan.steps.count, 5)
        XCTAssertEqual((0...5).map { plan.meshStep(after: $0) }, [0, 1, 1, 1, 1, 1])
        let meshDocument = try plan.meshPreviewDocument(at: 1, source: source)
        XCTAssertEqual(try meshDocument.editorContents().nodes.count, 1)
        XCTAssertEqual(meshDocument.encoded(), source.encoded())
        func animations(after step: Int) throws -> [DocumentAnimation] {
            try plan.previewDocument(after: step, source: source).animations()
        }
        XCTAssertTrue(try animations(after: 1).isEmpty)
        let added = try XCTUnwrap(try animations(after: 2).first)
        XCTAssertEqual(added.id, "walk")
        XCTAssertEqual(added.type, "Walk")
        XCTAssertTrue(added.parameters.isEmpty)
        XCTAssertEqual(try animations(after: 3).first?.parameters.map(\.name), ["duration"])
        XCTAssertEqual(try animations(after: 4).first?.parameters.map(\.name), ["speed", "duration"])
        XCTAssertEqual(try plan.previewDocument(after: 5, source: source).encoded(), source.encoded())
    }

    func testInvalidAnimationMetadataLeavesModelingReplayAvailable() throws {
        let source = try Dust3DDocument(snapshotXML: Data("""
            <canvas>
              <parts><part id="p"/></parts>
              <nodes><node id="n" partId="p" x="0" y="0" z="0" radius=".1"/></nodes>
              <animations><animation id="duplicate"/><animation id="duplicate"/></animations>
            </canvas>
            """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        XCTAssertEqual(plan.steps, [.node(id: "n", incomingEdgeID: nil)])
        XCTAssertNotNil(plan.animationMetadataError)
        XCTAssertEqual(try plan.previewDocument(after: 1, source: source).encoded(), source.encoded())
    }

    func testReplaySpeedUsesBoundedReferenceIntervals() {
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: 1), 2995)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: 11), 1445)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: 20), 50)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: .min), 2995)
        XCTAssertEqual(WorkflowReplaySpeed.intervalMilliseconds(for: .max), 50)
    }


    func testFinishesPartSettingsBeforeDrawingNextPart() throws {
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
        XCTAssertEqual(Array(plan.steps.prefix(4)), [
            .node(id: "a", incomingEdgeID: nil), .node(id: "b", incomingEdgeID: "ab"),
            .node(id: "c", incomingEdgeID: "bc"), .edge(id: "ca"),
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
        XCTAssertEqual(plan.steps.count, 10)
        let before = try plan.previewDocument(after: 4, source: document)
        XCTAssertFalse(String(decoding: before.modelXML, as: UTF8.self).contains("rounded="))
        XCTAssertFalse(String(decoding: before.modelXML, as: UTF8.self).contains("color="))
        let rounded = try plan.previewDocument(after: 5, source: document)
        XCTAssertTrue(String(decoding: rounded.modelXML, as: UTF8.self).contains("rounded=\"true\""))
        XCTAssertFalse(String(decoding: rounded.modelXML, as: UTF8.self).contains("color="))
        let colored = try plan.previewDocument(after: 6, source: document)
        XCTAssertTrue(String(decoding: colored.modelXML, as: UTF8.self).contains("color="))
        XCTAssertEqual(try colored.editorContents().parts.map(\.id), ["loop"])
        XCTAssertEqual(Array(plan.steps.dropLast().suffix(3)), [
            .node(id: "start", incomingEdgeID: nil), .node(id: "middle", incomingEdgeID: "backward"),
            .node(id: "end", incomingEdgeID: "forward"),
        ])
        let provisional = plan.frame(after: 9).edges.first { $0.id == "backward" }
        XCTAssertEqual(provisional?.fromID, "start")
        XCTAssertEqual(provisional?.toID, "middle")
        let previewEdge = try plan.previewDocument(after: 9, source: document).editorContents().edges
            .first { $0.id == "backward" }
        XCTAssertEqual(previewEdge, provisional)
        XCTAssertEqual(plan.frame(after: 10).edges.first { $0.id == "backward" }?.fromID, "middle")
        XCTAssertEqual(try plan.previewDocument(after: plan.steps.count, source: document).encoded(), document.encoded())

    }
}
