import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class GraphPartCrossSectionTests: XCTestCase {
    private let modelID = "{11111111-1111-4111-8111-111111111111}"
    private let profileID = "{22222222-2222-4222-8222-222222222222}"

    func testPresetLinkAndRotationKeepGraphSelectionAndUndoExactly() async throws {
        let source = try document()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let picks = try await session.selectGraph(nodes: ["a"], edges: ["edge"])
        let preset = try await session.editGraphPartCrossSection(
            .profile(.preset(.hexagon)), target: .init(snapshot: picks))
        XCTAssertEqual(preset.parts.first?.cutFace, .preset(.hexagon))
        let linked = try await session.editGraphPartCrossSection(
            .profile(.linkedPart(profileID)), target: .init(snapshot: preset))
        XCTAssertEqual(linked.parts.first?.cutFace, .linkedPart(profileID))
        let rotated = try await session.editGraphPartCrossSection(
            .rotation(PartCutRotationPreset.negativeQuarterTurn.halfTurns), target: .init(snapshot: linked))
        XCTAssertEqual(rotated.parts.first?.cutRotation, -0.5)
        let same = try await session.editGraphPartCrossSection(.rotation(-0.5), target: .init(snapshot: rotated))
        XCTAssertEqual(same.document.encoded(), rotated.document.encoded())
        XCTAssertEqual(same.documentRevision, rotated.documentRevision)
        XCTAssertEqual(same.selectedIDs, picks.selectedIDs)
        XCTAssertEqual(same.selectedEdgeIDs, picks.selectedEdgeIDs)
        XCTAssertTrue(same.parts.first?.isLocked == true)
        _ = try await session.undo()
        _ = try await session.undo()
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testCycleUnsupportedOwnerAndSelectionABARejectWithoutChangingSource() async throws {
        let source = try document(profileCutFace: modelID)
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let picked = try await session.selectGraph(nodes: [], edges: ["edge"])
        let target = GraphPartCrossSectionTarget(snapshot: picked)
        do {
            _ = try await session.editGraphPartCrossSection(.profile(.linkedPart(profileID)), target: target)
            XCTFail("A cyclic profile was accepted")
        } catch { XCTAssertEqual(error as? DocumentError, .cyclicProfile) }
        let profile = try await session.select("profile")
        XCTAssertNil(GraphPartCrossSectionTarget(snapshot: profile).part)
        _ = try await session.selectGraph(nodes: [], edges: ["edge"])
        do {
            _ = try await session.editGraphPartCrossSection(.rotation(0.5), target: target)
            XCTFail("Retained action acquired a later selection")
        } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }
        let mixed = try await session.selectGraph(nodes: ["a", "profile"], edges: [])
        XCTAssertNil(GraphPartCrossSectionTarget(snapshot: mixed).part)
        XCTAssertEqual(mixed.document.encoded(), source.encoded())
        XCTAssertFalse(mixed.canUndo)
    }

    func testGraphPartDeformationEditsResetIndependentlyAndUndoExactly() async throws {
        let source = try document()
        let session = EditorSession()
        _ = try await session.open(data: source.encoded())
        let picks = try await session.selectGraph(nodes: ["a"], edges: ["edge"])
        let width = try await session.editGraphPartCrossSection(
            .deformationScale(.width, 1.75), target: .init(snapshot: picks))
        let thickness = try await session.editGraphPartCrossSection(
            .deformationScale(.thickness, 0.25), target: .init(snapshot: width))
        let unified = try await session.editGraphPartCrossSection(
            .deformationUnified(true), target: .init(snapshot: thickness))
        let reset = try await session.editGraphPartCrossSection(
            .deformationScale(.width, 1), target: .init(snapshot: unified))
        let same = try await session.editGraphPartCrossSection(
            .deformationScale(.width, 1), target: .init(snapshot: reset))
        XCTAssertEqual(same.parts.first?.deformationScale(.width), 1)
        XCTAssertEqual(same.parts.first?.deformationScale(.thickness), 0.25)
        XCTAssertEqual(same.parts.first?.isDeformationUnified, true)
        let xml = try XMLDocument(data: same.document.modelXML)
        let taper = try xml.nodes(forXPath: "/canvas/nodes/node[@id='a']/@deformWidth")
        XCTAssertEqual(taper.map(\.stringValue), ["1.5"])
        XCTAssertEqual(same.selectedIDs, picks.selectedIDs)
        XCTAssertEqual(same.selectedEdgeIDs, picks.selectedEdgeIDs)
        XCTAssertEqual(same.document.encoded(), reset.document.encoded())
        XCTAssertEqual(same.documentRevision, reset.documentRevision)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), unified.document.encoded())
        _ = try await session.undo()
        _ = try await session.undo()
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), source.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testFailedReplacementRejectsCapturedCrossSectionAndDeformationEdits() async throws {
        let source = try document().encoded()
        let session = EditorSession()
        _ = try await session.open(data: source)
        let before = try await session.selectGraph(nodes: ["a"], edges: ["edge"])
        let target = GraphPartCrossSectionTarget(snapshot: before)
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid replacement opened")
        } catch {}
        let retained = try await session.animationSnapshot().editor
        XCTAssertTrue(target.isCurrent(in: retained))

        let edits: [GraphPartCrossSectionEdit] = [.rotation(0.5), .deformationScale(.width, 1.75)]
        for edit in edits {
            do {
                _ = try await session.editGraphPartCrossSection(edit, target: target)
                XCTFail("A captured edit reached the retained document")
            } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }
            let unchanged = try await session.animationSnapshot().editor
            XCTAssertEqual(unchanged.documentIdentity, before.documentIdentity)
            XCTAssertEqual(unchanged.documentRevision, before.documentRevision)
            XCTAssertEqual(unchanged.document.encoded(), source)
            XCTAssertFalse(unchanged.canUndo)
        }

        _ = try await session.open(data: source)
        let fresh = try await session.selectGraph(nodes: ["a"], edges: ["edge"])
        let edited = try await session.editGraphPartCrossSection(
            .rotation(0.5), target: .init(snapshot: fresh))
        XCTAssertEqual(edited.parts.first?.cutRotation, 0.5)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), source)
        XCTAssertFalse(restored.canUndo)
    }

    private func document(profileCutFace: String = "Quad") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='\(modelID)' deformWidth='1.5' x='.2' y='.5' z='.5' radius='.1'/>
                <node id='b' partId='\(modelID)' x='.8' y='.5' z='.5' radius='.1'/>
                <node id='profile' partId='\(profileID)' x='.5' y='.5' z='.5' radius='.1'/>
                </nodes><edges><edge id='edge' partId='\(modelID)' from='a' to='b'/></edges>
                <parts><part id='\(modelID)' locked='true' cutRotation='future'/>
                <part id='\(profileID)' target='CutFace' cutFace='\(profileCutFace)'/></parts>
                <components><component id='owner' linkDataType='partId' linkData='\(modelID)'/>
                <component id='profile-owner' linkDataType='partId' linkData='\(profileID)'/></components></canvas>
                """.utf8))
    }
}
