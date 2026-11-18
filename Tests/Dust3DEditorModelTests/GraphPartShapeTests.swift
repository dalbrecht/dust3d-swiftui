import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor
final class GraphPartShapeTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
                <node id='c' partId='q' x='2' y='0' z='0' radius='.1'/>
                <node id='orphan' x='3' y='0' z='0' radius='.1'/>
                <node id='alias' partId='caf&#233;' x='4' y='0' z='0' radius='.1'/>
                </nodes><edges><edge id='edge' partId='q' from='a' to='b'/></edges><parts>
                <part id='p' future='keep'/><part id='q' locked='true' chamfered='future' hard='future'/><part id='cafe&#769;'/>
                </parts></canvas>
                """.utf8))
    }

    func testExactGraphOwnerUsesStoredEdgePartAndDeclinesMissingOrMixedPicks() throws {
        var state = try EditorState(document: source())
        for (nodes, edges, owner) in [
            (Set(["a", "b"]), Set<String>(), Optional("p")),
            (Set(["c"]), Set(["edge"]), "q"),
            (Set<String>(), Set(["edge"]), "q"),
            (Set(["a"]), Set(["edge"]), nil),
            (Set(["orphan"]), Set(["edge"]), nil),
            (Set(["alias"]), Set<String>(), nil),
        ] {
            try state.selectGraph(nodes: nodes, edges: edges)
            let target = GraphPartShapeTarget(snapshot: state.snapshot)
            XCTAssertEqual(target.part?.id, owner)
            XCTAssertEqual(target.isCurrent(in: state.snapshot), owner != nil)
        }
    }

    func testOnlyExplicitOrImplicitModelPartsAdmitGraphShapeEdits() async throws {
        for role in [nil, "Model", "CutFace", "StitchingLine", "StitchingLoop", "ImportedModel", "FutureRole"] {
            let attribute = role.map { " target='\($0)'" } ?? ""
            let document = try Dust3DDocument(
                snapshotXML: Data(
                    """
                    <canvas><nodes><node id='node' partId='part' x='0' y='0' z='0' radius='.1'/></nodes>
                    <parts><part id='part'\(attribute) rounded='future'/></parts></canvas>
                    """.utf8))
            let session = EditorSession()
            _ = try await session.open(data: document.encoded())
            let snapshot = try await session.select("node")
            let target = GraphPartShapeTarget(snapshot: snapshot)
            if role == nil || role == "Model" {
                XCTAssertEqual(target.part?.target, .model)
                XCTAssertTrue(target.isCurrent(in: snapshot))
            } else {
                XCTAssertNil(target.part, "Unexpected graph shape eligibility for \(role ?? "default")")
                XCTAssertFalse(target.isCurrent(in: snapshot))
                do {
                    _ = try await session.setGraphPartShape(.roundedEnds, value: true, target: target)
                    XCTFail("A non-Model graph owner accepted a shape edit")
                } catch { XCTAssertEqual(error as? GraphPartShapeError, .staleTarget) }
                let after = try await session.select("node")
                XCTAssertEqual(after.document.encoded(), document.encoded())
                XCTAssertFalse(after.canUndo)
            }
        }
    }

    func testCapturedShapeEditsPreserveGraphPicksAndUndoExactlyEvenWhenPartLocked() async throws {
        let original = try source()
        for property in [PartModifierProperty.subdivision, .chamfer, .roundedEnds] {
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            let selected = try await session.selectGraph(nodes: ["c"], edges: ["edge"])
            let target = GraphPartShapeTarget(snapshot: selected)
            let value = property != .chamfer
            let changed = try await session.setGraphPartShape(property, value: value, target: target)
            let part = try XCTUnwrap(changed.parts.first { $0.id == "q" })
            XCTAssertEqual(part.modifierValue(property), value)
            if property != .chamfer { XCTAssertNil(part.modifierValue(.chamfer)) }
            XCTAssertTrue(part.isLocked)
            XCTAssertEqual(changed.selectedIDs, selected.selectedIDs)
            XCTAssertEqual(changed.selectedEdgeIDs, selected.selectedEdgeIDs)
            XCTAssertNotEqual(changed.previewIdentity, selected.previewIdentity)
            XCTAssertTrue(changed.canUndo)
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), original.encoded())
            XCTAssertFalse(undone.canUndo)
        }
    }

    func testRetainedTargetRejectsSelectionABA() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.selectGraph(nodes: ["a", "b"], edges: [])
        let target = GraphPartShapeTarget(snapshot: before)
        _ = try await session.select("c")
        _ = try await session.selectGraph(nodes: ["a", "b"], edges: [])
        do {
            _ = try await session.setGraphPartShape(.roundedEnds, value: true, target: target)
            XCTFail("Retained action acquired a later selection epoch")
        } catch { XCTAssertEqual(error as? GraphPartShapeError, .staleTarget) }
        let after = try await session.selectGraph(nodes: ["a", "b"], edges: [])
        XCTAssertEqual(after.document.encoded(), original.encoded())
        XCTAssertFalse(after.canUndo)
    }
    func testSurfaceModifiersUseOneCapturedOwnerAndExactUndo() async throws {
        let original = try source().encoded()
        XCTAssertTrue(GraphPartShapeTarget.properties.contains(.hardJoin))
        XCTAssertTrue(GraphPartShapeTarget.properties.contains(.interpolation))
        for (property, value) in [(PartModifierProperty.hardJoin, false), (.interpolation, false)] {
            let session = EditorSession()
            _ = try await session.open(data: original)
            let before = try await session.selectGraph(nodes: ["c"], edges: ["edge"])
            let target = GraphPartShapeTarget(snapshot: before)
            XCTAssertNil(target.part?.modifierValue(.hardJoin))
            XCTAssertEqual(target.part?.modifierValue(.interpolation), true)
            let changed = try await session.setGraphPartShape(property, value: value, target: target)
            let part = try XCTUnwrap(changed.parts.first { $0.id == "q" })
            XCTAssertEqual(part.modifierValue(property), value)
            if property == .hardJoin {
                XCTAssertEqual(part.modifierValue(.interpolation), true)
            } else {
                XCTAssertNil(part.modifierValue(.hardJoin))
            }
            XCTAssertNil(part.modifierValue(.chamfer))
            XCTAssertTrue(part.isLocked)
            XCTAssertEqual(changed.parts.first { $0.id == "p" }?.modifierValue(.interpolation), true)
            XCTAssertEqual(changed.parts.first { $0.id == "p" }?.modifierValue(.hardJoin), false)
            XCTAssertEqual(changed.selectedIDs, before.selectedIDs)
            XCTAssertEqual(changed.selectedEdgeIDs, before.selectedEdgeIDs)
            XCTAssertNotEqual(changed.previewIdentity, before.previewIdentity)
            let same = try await session.setGraphPartShape(property, value: value, target: .init(snapshot: changed))
            XCTAssertEqual(same.document.encoded(), changed.document.encoded())
            XCTAssertEqual(same.documentRevision, changed.documentRevision)
            let undone = try await session.undo()
            XCTAssertEqual(undone.document.encoded(), original)
            XCTAssertFalse(undone.canUndo)
        }
    }

    func testFailedReplacementRejectsRetainedShapeTarget() async throws {
        let original = try source().encoded()
        let session = EditorSession()
        _ = try await session.open(data: original)
        let before = try await session.select("a")
        let target = GraphPartShapeTarget(snapshot: before)
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid replacement opened")
        } catch {}
        let retained = try await session.animationSnapshot().editor
        XCTAssertTrue(target.isCurrent(in: retained))
        do {
            _ = try await session.setGraphPartShape(.roundedEnds, value: true, target: target)
            XCTFail("The failed replacement retained a writable target")
        } catch { XCTAssertEqual(error as? GraphPartShapeError, .staleTarget) }
        let unchanged = try await session.animationSnapshot().editor
        XCTAssertEqual(unchanged.document.encoded(), original)
        XCTAssertEqual(unchanged.documentRevision, before.documentRevision)
        XCTAssertFalse(unchanged.canUndo)
    }

}
