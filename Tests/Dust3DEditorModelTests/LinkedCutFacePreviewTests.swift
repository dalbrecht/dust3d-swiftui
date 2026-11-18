import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class LinkedCutFacePreviewTests: XCTestCase {
    private let profile = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"

    func testOpenChainUsesBothRadiusOffsetsInFrontPlaneWithoutEditingArchive() throws {
        let state = try state(
            nodes: [("b", 2, 0, 9, 0.5), ("a", 0, 0, -4, 0.5)],
            edges: [("b", "a")])
        let before = state.snapshot.document.encoded()
        XCTAssertEqual(
            LinkedCutFacePreview.contour(partID: profile, snapshot: state.snapshot),
            [.init(x: -1, y: -0.5), .init(x: 1, y: -0.5), .init(x: 1, y: 0.5), .init(x: -1, y: 0.5)])
        XCTAssertNil(
            LinkedCutFacePreview.contour(
                partID: String(profile.dropFirst().dropLast()), snapshot: state.snapshot))
        XCTAssertEqual(state.snapshot.document.encoded(), before)
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testClosedRingUsesCentersIgnoresRadiusAndKeepsCounterclockwiseContour() throws {
        let state = try state(
            nodes: [("a", 0, 0, 0, 0.01), ("b", 2, 0, 1, 0.4), ("c", 2, 1, 2, 0.2), ("d", 0, 1, 3, 1)],
            edges: [("d", "a"), ("a", "b"), ("c", "d"), ("b", "c")])
        XCTAssertEqual(
            LinkedCutFacePreview.contour(partID: profile, snapshot: state.snapshot),
            [.init(x: -1, y: -0.5), .init(x: 1, y: -0.5), .init(x: 1, y: 0.5), .init(x: -1, y: 0.5)])
    }

    func testBentChainUsesAverageTangentAndVariableRadii() throws {
        let state = try state(
            nodes: [("a", 0, 1, 0, 0.25), ("b", 1, 1, 0, 0.5), ("c", 1, 0, 0, 0.125)],
            edges: [("b", "a"), ("b", "c")])
        let points = try XCTUnwrap(LinkedCutFacePreview.contour(partID: profile, snapshot: state.snapshot))
        XCTAssertEqual(points.count, 6)
        XCTAssertEqual(points[1].y, -1, accuracy: 0.000_001)
        XCTAssertEqual(points[2].y, 1, accuracy: 0.000_001)
        XCTAssertEqual(points[1].x - points[4].x, sqrt(2) / (1 + sqrt(0.125)), accuracy: 0.000_001)
        XCTAssertTrue(points.allSatisfy { (-1...1).contains($0.x) && (-1...1).contains($0.y) })
    }

    func testRejectsDisconnectedBranchedCoincidentAndOverBudgetProfiles() throws {
        let points: [(String, Double, Double, Double, Double)] = [
            ("a", 0, 0, 0, 0.1), ("b", 1, 0, 0, 0.1), ("c", 0, 1, 0, 0.1), ("d", 1, 1, 0, 0.1),
        ]
        for edges in [[("a", "b"), ("c", "d")], [("a", "b"), ("a", "c"), ("a", "d")], [("a", "b")]] {
            let state = try state(nodes: points, edges: edges)
            XCTAssertNil(LinkedCutFacePreview.contour(partID: profile, snapshot: state.snapshot))
        }
        let coincident = try state(nodes: [points[0], ("b", 0, 0, 5, 0.1)], edges: [("a", "b")])
        XCTAssertNil(LinkedCutFacePreview.contour(partID: profile, snapshot: coincident.snapshot))
        let tooMany = LinkedCutFacePreview.maximumNodes + 1
        let long = try state(
            nodes: (0..<tooMany).map { ("n\($0)", Double($0), 0, 0, 0.1) },
            edges: (1..<tooMany).map { ("n\($0 - 1)", "n\($0)") })
        XCTAssertNil(LinkedCutFacePreview.contour(partID: profile, snapshot: long.snapshot))
    }

    private func state(
        nodes: [(id: String, x: Double, y: Double, z: Double, radius: Double)], edges: [(String, String)]
    ) throws -> EditorState {
        let nodeXML = nodes.map {
            "<node id='\($0.id)' partId='\(profile)' x='\($0.x)' y='\($0.y)' z='\($0.z)' radius='\($0.radius)'/>"
        }.joined()
        let edgeXML = edges.enumerated().map { i, edge in
            "<edge id='e\(i)' partId='\(profile)' from='\(edge.0)' to='\(edge.1)'/>"
        }.joined()
        let xml = """
            <canvas><nodes>\(nodeXML)</nodes><edges>\(edgeXML)</edges>
            <parts><part id='\(profile)' target='CutFace'/></parts></canvas>
            """
        return try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
    }
}
