import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class CanvasRotationTests: XCTestCase {
    private func document(origin: Bool = true, flags: String = "", cycle: Bool = false) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas \(origin ? "originX='0' originY='0' originZ='0'" : "")><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='1' z='1' radius='.2'/>
                <node id='c' partId='q' x='2' y='1' z='3' radius='.3'/>
                <node id='d' partId='p' x='3' y='1' z='4' radius='.4'/>
                </nodes><edges><edge id='ab' from='a' to='b' partId='p'/><edge id='bc' from='b' to='c' partId='p'/><edge id='cd' from='c' to='d' partId='p'/>\(cycle ? "<edge id='da' from='d' to='a' partId='p'/>" : "")</edges><parts><part id='p'/><part id='q' \(flags)/></parts></canvas>
                """.utf8))
    }
    func testGeneralAngleMixedUnionDeduplicatesAndRetainsSelectionRadiiHistory() throws {
        for plane in EditingPlane.allCases {
            let source = try document()
            var state = try EditorState(document: source)
            try state.selectGraph(nodes: ["b"], edges: ["bc"])
            try state.rotateSelection(degrees: 30, plane: plane)
            let b = try state.snapshot.document.node(id: "b")
            let c = try state.snapshot.document.node(id: "c")
            let horizontalDelta = plane == .front ? 0.5 : 1.0
            XCTAssertEqual(b.position.y, 1 - horizontalDelta * 0.5, accuracy: 1e-12)
            XCTAssertEqual(c.position.y, 1 + horizontalDelta * 0.5, accuracy: 1e-12)
            let center = plane == .front ? 1.5 : 2.0
            let actual = plane == .front ? b.position.x : b.position.z
            XCTAssertEqual(actual, center - horizontalDelta * cos(.pi / 6), accuracy: 1e-12)
            XCTAssertEqual(plane == .front ? b.position.z : b.position.x, 1)
            XCTAssertEqual(b.radius, 0.2)
            XCTAssertEqual(state.snapshot.selectedIDs, ["b"])
            XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["bc"])
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }
    func testAutomaticPivotParentEndpointCycleAndMissingOrigin() throws {
        var state = try EditorState(document: document())
        try state.select("b")
        try state.rotateSelection(degrees: 90, plane: .front)
        XCTAssertEqual(try state.snapshot.document.node(id: "c").position.x, 1, accuracy: 1e-12)
        XCTAssertEqual(try state.snapshot.document.node(id: "c").position.y, 2, accuracy: 1e-12)
        XCTAssertEqual(try state.snapshot.document.node(id: "a").position.x, 0)
        var cycle = try EditorState(document: document(cycle: true))
        try cycle.select("b")
        try cycle.rotateSelection(degrees: 90, plane: .front)
        XCTAssertEqual(try cycle.snapshot.document.node(id: "a").position.x, 2, accuracy: 1e-12)
        var endpoint = try EditorState(document: document())
        try endpoint.select("a")
        try endpoint.rotateSelection(degrees: 30, plane: .side)
        XCTAssertNotEqual(try endpoint.snapshot.document.node(id: "d").position.z, 4)
        var absent = try EditorState(document: document(origin: false))
        try absent.select("b")
        try absent.rotateSelection(degrees: 30, plane: .front)
        XCTAssertFalse(absent.snapshot.canUndo)
    }
    func testNoopsInvalidAnglesAndStaleTargetsPreserveRedoAndAtomicity() throws {
        var state = try EditorState(document: document())
        try state.selectGraph(nodes: ["a", "b"], edges: [])
        try state.rotateSelection(degrees: -17.5, plane: .side)
        try state.undo()
        let before = state.snapshot.document.encoded()
        for degrees in [0.0, 360, -720] { try state.rotateSelection(degrees: degrees, plane: .front) }
        XCTAssertTrue(state.snapshot.canRedo)
        for degrees in [Double.nan, .infinity, Double(Int32.max) + 1] {
            XCTAssertThrowsError(try state.rotateSelection(degrees: degrees, plane: .front))
            XCTAssertEqual(state.snapshot.document.encoded(), before)
        }
        let target = CanvasAdjustmentTarget(snapshot: state.snapshot)
        try state.select("c")
        XCTAssertThrowsError(try state.rotateSelection(degrees: 1, plane: .front, target: target)) {
            XCTAssertEqual($0 as? EditorError, .staleCanvasAdjustment)
        }
    }
    func testEdgeOnlyAndNoOriginGroupOneDegreeSignedOracleAndReadonlyPivot() throws {
        for plane in EditingPlane.allCases {
            for degrees in [-1.0, 1.0] {
                var state = try EditorState(document: document(origin: false))
                try state.selectEdges(["bc"])
                try state.rotateSelection(degrees: degrees, plane: plane)
                let node = try state.snapshot.document.node(id: "c")
                let delta = plane == .front ? 0.5 : 1.0
                XCTAssertEqual(node.position.y, 1 + delta * sin(degrees * .pi / 180), accuracy: 1e-12)
                XCTAssertEqual(
                    plane == .front ? node.position.x : node.position.z,
                    (plane == .front ? 1.5 : 2) + delta * cos(degrees * .pi / 180), accuracy: 1e-12)
                XCTAssertTrue(state.snapshot.selectedIDs.isEmpty)
                XCTAssertEqual(state.snapshot.selectedEdgeIDs, ["bc"])
            }
        }
        var locked = try EditorState(document: document(flags: "locked='true'"))
        try locked.select("c")
        XCTAssertThrowsError(try locked.rotateSelection(degrees: 1, plane: .front)) {
            XCTAssertEqual($0 as? EditorError, .readOnlyNode)
        }
        XCTAssertFalse(locked.snapshot.canUndo)
    }
    func testStaleDocumentAndConstraintEpochsRejectAndReadonlyGroupCentroidUsesEditableNodes() throws {
        var state = try EditorState(document: document())
        try state.selectEdges(["bc"])
        let target = CanvasAdjustmentTarget(snapshot: state.snapshot)
        state.setLock(.x, isLocked: true)
        state.setLock(.x, isLocked: false)
        XCTAssertThrowsError(try state.rotateSelection(degrees: 10, plane: .front, target: target))
        let current = CanvasAdjustmentTarget(snapshot: state.snapshot)
        try state.rotateSelection(degrees: 10, plane: .front)
        XCTAssertThrowsError(try state.rotateSelection(degrees: 10, plane: .front, target: current))
        var restricted = try EditorState(document: document(origin: false, flags: "locked='true'"))
        try restricted.selectGraph(nodes: ["a", "b", "c"], edges: [])
        try restricted.rotateSelection(degrees: 90, plane: .front)
        XCTAssertEqual(try restricted.snapshot.document.node(id: "a").position, .init(x: 1, y: 0, z: 0))
        XCTAssertEqual(try restricted.snapshot.document.node(id: "c").position, .init(x: 2, y: 1, z: 3))
    }
    func testOutOfBoundsRotationRejectsWholeBatchWithoutHistoryOrPreviewChange() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='1000000' y='1000000' z='0' radius='.1'/><node id='b' partId='p' x='-1000000' y='-1000000' z='0' radius='.1'/></nodes><edges/><parts><part id='p'/></parts></canvas>
                """.utf8))
        var state = try EditorState(document: source)
        try state.selectGraph(nodes: ["a", "b"], edges: [])
        let identity = state.snapshot.previewIdentity
        XCTAssertThrowsError(try state.rotateSelection(degrees: 45, plane: .front))
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
        XCTAssertEqual(state.snapshot.previewIdentity, identity)
        XCTAssertFalse(state.snapshot.canUndo)
    }
    func testCardinalAnglesEmptyAndReadonlyNoops() throws {
        for degrees in [90.0, -90, 180, -180, 270, -270] {
            var state = try EditorState(document: document(origin: false))
            try state.selectGraph(nodes: ["a", "b"], edges: [])
            try state.rotateSelection(degrees: degrees, plane: .front)
            let angle = degrees * Double.pi / 180
            let node = try state.snapshot.document.node(id: "b")
            XCTAssertEqual(node.position.x, 0.5 + 0.5 * cos(angle) - 0.5 * sin(angle), accuracy: 1e-12)
            XCTAssertEqual(node.position.y, 0.5 + 0.5 * sin(angle) + 0.5 * cos(angle), accuracy: 1e-12)
        }
        var empty = try EditorState(document: document())
        try empty.selectGraph(nodes: [], edges: [])
        try empty.rotateSelection(degrees: 1, plane: .front)
        XCTAssertFalse(empty.snapshot.canUndo)
        let readonly = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p' x='1' y='1' z='1' radius='.1'/></nodes><edges/><parts><part id='p' locked='true'/></parts></canvas>
                """.utf8))
        var fixed = try EditorState(document: readonly)
        try fixed.selectGraph(nodes: ["a", "b"], edges: [])
        try fixed.rotateSelection(degrees: 1, plane: .front)
        XCTAssertFalse(fixed.snapshot.canUndo)
    }
    func testNativeAxisAndReadonlyLocksRemainEffective() throws {
        var state = try EditorState(document: document(flags: "locked='true'"))
        try state.select("b")
        state.setLock(.y, isLocked: true)
        let c = try state.snapshot.document.node(id: "c")
        try state.rotateSelection(degrees: 45, plane: .front)
        XCTAssertEqual(try state.snapshot.document.node(id: "c"), c)
        XCTAssertEqual(try state.snapshot.document.node(id: "d").position.y, 1)
    }
}
