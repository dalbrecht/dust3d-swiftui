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

    private func document(profileCutFace: String = "Quad") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='\(modelID)' x='.2' y='.5' z='.5' radius='.1'/>
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
