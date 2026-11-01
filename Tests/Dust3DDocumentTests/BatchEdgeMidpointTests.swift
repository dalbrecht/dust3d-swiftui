import Foundation
import XCTest

@testable import Dust3DDocument

final class BatchEdgeMidpointTests: XCTestCase {
    private func document(nodeCount: Int = 3) throws -> Dust3DDocument {
        let nodes = (0..<nodeCount).map { "<node id='n\($0)' partId='p' x='\($0)' y='0' z='0' radius='1'/>" }.joined()
        return try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes>\(nodes)</nodes><edges><edge id='z' partId='p' from='n0' to='n1' name='Z' boneName='BoneZ' opaque='retained'><future/></edge><edge id='a' partId='p' from='n1' to='n2' name='A' boneName='BoneA'/></edges><parts><part id='p'/></parts><components/></canvas>"
                    .utf8))
    }

    func testAdjacentBatchRetainsMetadataDirectionAndUUIDOrderInOneHistoryEntry() throws {
        let original = try document()
        XCTAssertTrue(original.canInsertEdgeMidpoints(ids: ["z", "a"]))
        var history = DocumentHistory(document: original)
        try history.apply(
            .insertEdgeMidpoints([
                .init(originalEdgeID: "z", nodeID: "mz", edgeID: "tz"),
                .init(originalEdgeID: "a", nodeID: "ma", edgeID: "ta"),
            ]))
        let contents = try history.document.editorContents()
        XCTAssertEqual(Array(contents.nodes.suffix(2).map(\.id)), ["ma", "mz"])
        XCTAssertEqual(contents.edges.map(\.id), ["z", "a", "ta", "tz"])
        XCTAssertEqual(contents.edges.map(\.fromID), ["n0", "n1", "ma", "mz"])
        XCTAssertEqual(contents.edges.map(\.toID), ["mz", "ma", "n2", "n1"])
        XCTAssertEqual(contents.edges.map(\.boneName), ["BoneZ", "BoneA", "BoneA", "BoneZ"])
        let xml = try XMLDocument(data: history.document.modelXML)
        XCTAssertEqual(try xml.nodes(forXPath: "/canvas/edges/edge[@opaque='retained']").count, 1)
        XCTAssertEqual(try xml.nodes(forXPath: "/canvas/edges/edge[@id='tz']/future").count, 0)
        let edited = history.document.encoded()
        XCTAssertTrue(history.undo())
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited)
    }

    func testAggregateQuotaDuplicatePicksAndFreshIdentityCollisionRejectAtomically() throws {
        let bounded = try document(nodeCount: 9999)
        XCTAssertTrue(bounded.canInsertEdgeMidpoints(ids: ["a"]))
        XCTAssertFalse(bounded.canInsertEdgeMidpoints(ids: ["a", "z"]))
        var history = DocumentHistory(document: bounded)
        XCTAssertThrowsError(
            try history.apply(
                .insertEdgeMidpoints([
                    .init(originalEdgeID: "a", nodeID: "ma", edgeID: "ta"),
                    .init(originalEdgeID: "z", nodeID: "mz", edgeID: "tz"),
                ]))
        ) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
        XCTAssertEqual(history.document.encoded(), bounded.encoded())
        let original = try document()
        XCTAssertFalse(original.canInsertEdgeMidpoints(ids: ["a", "a"]))
        XCTAssertFalse(original.canInsertEdgeMidpoints(ids: []))
        XCTAssertThrowsError(
            try original.applying(
                .insertEdgeMidpoints([
                    .init(originalEdgeID: "a", nodeID: "same", edgeID: "ta"),
                    .init(originalEdgeID: "z", nodeID: "same", edgeID: "tz"),
                ])))
    }
    func testBoundedWholeChainBatchUsesOneCapturedUUIDOrderAndOneHistoryStep() throws {
        let nodeXML = (0...32).map { "<node id='n\($0)' partId='p' x='\($0)' y='0' z='0' radius='1'/>" }.joined()
        let ids = (0..<32).map { "{00000000-0000-4000-8000-" + String(format: "%012x", $0) + "}" }
        let edgeXML = ids.enumerated().map {
            "<edge id='\($0.element)' partId='p' from='n\($0.offset)' to='n\($0.offset+1)'/>"
        }.joined()
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes>\(nodeXML)</nodes><edges>\(edgeXML)</edges><parts><part id='p'/></parts></canvas>".utf8)
        )
        XCTAssertTrue(original.canInsertEdgeMidpoints(ids: Array(ids.reversed())))
        let requests = ids.enumerated().reversed().map {
            EdgeMidpointInsertion(originalEdgeID: $0.element, nodeID: "m\($0.offset)", edgeID: "t\($0.offset)")
        }
        var history = DocumentHistory(document: original)
        try history.apply(.insertEdgeMidpoints(requests))
        let contents = try history.document.editorContents()
        XCTAssertEqual(contents.nodes.count, 65)
        XCTAssertEqual(contents.edges.count, 64)
        XCTAssertEqual(Array(contents.nodes.suffix(32).map(\.id)), (0..<32).map { "m\($0)" })
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
    }

}
