import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class OrthogonalQuarterTurnTests: XCTestCase {
    private func source(locked: Bool = false) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas originX='0' originY='0' originZ='0'><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='q' x='2' y='4' z='6' radius='.2'/>
                </nodes><edges><edge id='ab' from='a' to='b' partId='p'/></edges>
                <parts><part id='p'/><part id='q' locked='\(locked)'/></parts></canvas>
                """.utf8))
    }

    func testSignedTurnsUseOrthogonalAxesAndDeduplicatedCentroid() throws {
        let original = try source()
        let cases: [(EditingPlane, OrthogonalQuarterTurn, NodePosition)] = [
            (.front, .positive, .init(x: 0, y: 5, z: 1)),
            (.front, .negative, .init(x: 0, y: -1, z: 5)),
            (.side, .positive, .init(x: -1, y: 3, z: 0)),
            (.side, .negative, .init(x: 3, y: 1, z: 0)),
        ]
        for (profile, turn, expected) in cases {
            var state = try EditorState(document: original)
            try state.selectGraph(nodes: ["a"], edges: ["ab"])
            XCTAssertTrue(state.snapshot.canRotateOrthogonalQuarterTurn(from: profile))
            try state.rotateOrthogonalQuarterTurn(turn, from: profile)
            let node = try state.snapshot.document.node(id: "a")
            XCTAssertEqual(node.position, expected)
            XCTAssertEqual(node.radius, 0.1)
            XCTAssertEqual(state.snapshot.selectedIDs, ["a"])
            XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["ab"])
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testReadonlyParticipantsInfluenceCentroidAndAxisLocksMaskOnlyTheirCoordinates() throws {
        let original = try source(locked: true)
        var state = try EditorState(document: original)
        try state.selectGraph(nodes: ["a", "b"], edges: [])
        state.setLock(.y, isLocked: true)
        let stale = CanvasAdjustmentTarget(snapshot: state.snapshot)
        state.setLock(.z, isLocked: true)
        XCTAssertFalse(state.snapshot.canRotateOrthogonalQuarterTurn(from: .front))
        try state.rotateOrthogonalQuarterTurn(.positive, from: .front)
        XCTAssertFalse(state.snapshot.canUndo)
        state.setLock(.z, isLocked: false)
        XCTAssertThrowsError(try state.rotateOrthogonalQuarterTurn(.positive, from: .front, target: stale)) {
            XCTAssertEqual($0 as? EditorError, .staleCanvasAdjustment)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        try state.rotateOrthogonalQuarterTurn(.positive, from: .front)
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position, .init(x: 0, y: 0, z: 1))
        XCTAssertEqual(try state.snapshot.document.node(id: "b"), try original.node(id: "b"))
    }

    func testEdgeOnlyAndSingleNodeDoNotRotateOrPivotDescendants() throws {
        let original = try source()
        var state = try EditorState(document: original)
        try state.selectEdges(["ab"])
        XCTAssertFalse(state.snapshot.canRotateOrthogonalQuarterTurn(from: .side))
        try state.rotateOrthogonalQuarterTurn(.positive, from: .side)
        try state.select("a")
        XCTAssertFalse(state.snapshot.canRotateOrthogonalQuarterTurn(from: .side))
        try state.rotateOrthogonalQuarterTurn(.positive, from: .side)
        XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }
    @MainActor
    func testActorRejectsRetainedSourceAfterFailedReplacement() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        let target = CanvasAdjustmentTarget(snapshot: selected)
        do {
            _ = try await session.open(data: Data("not a DS3".utf8))
            XCTFail("Malformed replacement was accepted")
        } catch {}
        do {
            _ = try await session.rotateOrthogonalQuarterTurn(.positive, from: .front, target: target)
            XCTFail("Retired source accepted a rotation")
        } catch {
            XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment)
        }
        let retained = try await session.selectGraph(nodes: ["a"], edges: ["ab"])
        XCTAssertEqual(retained.document.encoded(), original.encoded())
        XCTAssertFalse(retained.canUndo)
    }

}
