import Foundation
import XCTest

@testable import Dust3DDocument

final class EdgeMidpointTests: XCTestCase {
    private func document(state: String = "", transform: (String) -> String = { $0 }) throws -> Dust3DDocument {
        let model = Data(
            transform(
                "<canvas future='retained'><nodes><node id='a' partId='p' x='-2' y='4' z='6' radius='2'/><node id='b' partId='p' x='6' y='-2' z='2' radius='4'/></nodes><edges><edge id='e' partId='p' from='a' to='b' name='Edge' boneName='Root' future='opaque'><future/></edge></edges><parts><part id='p' \(state)/></parts><components><component id='c' linkData='p' linkDataType='partId'/></components><future value='yes'/></canvas>"
            ).utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='3'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let offset = prefix.count + 10 + 1 + header.utf8.count
        return try Dust3DDocument(
            data: Data("\(prefix)\(String(format: "%010d", offset))\n\(header)".utf8) + model + Data([1, 2, 3]))
    }

    func testMidpointPreservesDirectionMetadataAssetsAndOneHistoryEntry() throws {
        let original = try document()
        var history = DocumentHistory(document: original)
        let identity = history.previewIdentity
        try history.apply(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second"))
        let contents = try history.document.editorContents()
        XCTAssertEqual(contents.nodes.last?.value, EditableNode(position: .init(x: 2, y: 1, z: 4), radius: 3))
        XCTAssertEqual(contents.nodes.last?.partID, "p")
        XCTAssertEqual(contents.edges.map(\.fromID), ["a", "middle"])
        XCTAssertEqual(contents.edges.map(\.toID), ["middle", "b"])
        XCTAssertEqual(contents.edges.map(\.id), ["e", "second"])
        XCTAssertEqual(contents.edges.map(\.boneName), ["Root", "Root"])
        XCTAssertNotEqual(history.previewIdentity, identity)
        let edited = history.document.encoded()
        let xml = try XMLDocument(data: history.document.modelXML)
        let edges = try xml.nodes(forXPath: "/canvas/edges/edge").compactMap { $0 as? XMLElement }
        XCTAssertEqual(edges.map { $0.attribute(forName: "name")?.stringValue }, ["Edge", "Edge"])
        XCTAssertEqual(edges.first?.attribute(forName: "future")?.stringValue, "opaque")
        XCTAssertNil(edges.last?.attribute(forName: "future"))
        XCTAssertEqual(edges.first?.elements(forName: "future").count, 1)
        XCTAssertEqual(edges.last?.elements(forName: "future").count, 0)
        XCTAssertEqual(xml.rootElement()?.attribute(forName: "future")?.stringValue, "retained")
        XCTAssertEqual(history.document.asset(named: "opaque"), Data([1, 2, 3]))
        XCTAssertEqual(try Dust3DDocument(data: edited).editorContents().nodes, contents.nodes)
        XCTAssertEqual(try Dust3DDocument(data: edited).editorContents().edges, contents.edges)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertEqual(history.previewIdentity, identity)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited)
        history.markSaved(history.document)
        XCTAssertFalse(history.isDirty)
    }

    func testRejectedCommandsPreserveArchiveHistoryAndPreviewIdentity() throws {
        for state in ["", "locked='true'", "visible='false'", "disabled='true'"] {
            let original = try document(state: state)
            for command in [
                DocumentCommand.insertEdgeMidpoint(id: "missing", nodeID: "middle", edgeID: "second"),
                .insertEdgeMidpoint(id: "e", nodeID: "a", edgeID: "second"),
                .insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "p"),
                .insertEdgeMidpoint(id: "e", nodeID: "same", edgeID: "same"),
                .insertEdgeMidpoint(id: "e", nodeID: "", edgeID: "second"),
            ] {
                var history = DocumentHistory(document: original)
                let identity = history.previewIdentity
                XCTAssertThrowsError(try history.apply(command))
                XCTAssertEqual(history.document.encoded(), original.encoded())
                XCTAssertEqual(history.previewIdentity, identity)
                XCTAssertFalse(history.canUndo)
            }
            if !state.isEmpty {
                XCTAssertThrowsError(
                    try original.applying(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second")))
            }
        }
    }
    func testRejectsMismatchedOwnershipSelfLoopsAndIdentityAliases() throws {
        for transform: (String) -> String in [
            { $0.replacingOccurrences(of: "id='e' partId='p'", with: "id='e' partId='other'") },
            { $0.replacingOccurrences(of: "to='b'", with: "to='a'") },
            {
                $0.replacingOccurrences(of: "id='b' partId='p'", with: "id='b' partId='other'")
                    .replacingOccurrences(of: "<parts>", with: "<parts><part id='other'/>")
            },
        ] {
            let original = try document(transform: transform)
            XCTAssertThrowsError(
                try original.applying(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second")))
        }
        let original = try document()
        for id in ["c", "e", "p", String(repeating: "x", count: 129), "bad\nidentity"] {
            XCTAssertThrowsError(try original.applying(.insertEdgeMidpoint(id: "e", nodeID: id, edgeID: "second")))
        }
    }

    func testFiniteBoundaryMidpointAndRejectedCommandPreserveRedo() throws {
        let original = try document {
            $0.replacingOccurrences(of: "x='-2'", with: "x='1000000'")
                .replacingOccurrences(of: "x='6'", with: "x='1000000'")
        }
        var history = DocumentHistory(document: original)
        try history.apply(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second"))
        XCTAssertEqual(try history.document.editorContents().nodes.last?.value.position.x, 1_000_000)
        XCTAssertTrue(history.undo())
        let identity = history.previewIdentity
        XCTAssertThrowsError(try history.apply(.insertEdgeMidpoint(id: "e", nodeID: "a", edgeID: "second")))
        XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.previewIdentity, identity)
        XCTAssertEqual(history.document.encoded(), original.encoded())
    }

    func testGraphCountBoundsRejectAtomically() throws {
        let node = "<node id='extraINDEX' partId='p' x='0' y='0' z='0' radius='1'/>"
        let edge = "<edge id='extraINDEX' partId='p' from='a' to='b'/>"
        for (closing, template, count) in [("</nodes>", node, 9998), ("</edges>", edge, 19999)] {
            let original = try document { xml in
                xml.replacingOccurrences(
                    of: closing,
                    with: (0..<count).map {
                        template.replacingOccurrences(of: "INDEX", with: String($0))
                    }.joined() + closing)
            }
            var history = DocumentHistory(document: original)
            XCTAssertThrowsError(try history.apply(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second"))) {
                XCTAssertEqual($0 as? DocumentError, .limitExceeded)
            }
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertFalse(history.canUndo)
        }
    }

    func testUUIDAliasesAndNonfiniteSourceGeometryAreRejected() throws {
        let uuid = "00000000-0000-4000-8000-000000000001"
        let original = try document { $0.replacingOccurrences(of: "id='c'", with: "id='{\(uuid)}'") }
        XCTAssertThrowsError(try original.applying(.insertEdgeMidpoint(id: "e", nodeID: uuid, edgeID: "second")))
        XCTAssertThrowsError(
            try original.applying(
                .insertEdgeMidpoint(
                    id: "e", nodeID: "{00000000-0000-4000-8000-000000000002}",
                    edgeID: "00000000-0000-4000-8000-000000000002")))
        for scalar in ["nan", "inf", "1000001"] {
            let malformed = try document { $0.replacingOccurrences(of: "x='-2'", with: "x='\(scalar)'") }
            XCTAssertThrowsError(
                try malformed.applying(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second")))
        }
    }

    func testMidpointParticipatesInOneCancelableTransaction() throws {
        let original = try document()
        var history = DocumentHistory(document: original)
        let identity = history.previewIdentity
        try history.beginTransaction()
        try history.apply(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second"))
        history.cancelTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertEqual(history.previewIdentity, identity)
        XCTAssertFalse(history.canUndo)
        try history.beginTransaction()
        try history.apply(.insertEdgeMidpoint(id: "e", nodeID: "middle", edgeID: "second"))
        try history.endTransaction()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
    }

    func testAvailabilityIsReadOnlyAndMatchesStructuralRejection() throws {
        let original = try document()
        let bytes = original.encoded()
        XCTAssertTrue(original.canInsertEdgeMidpoint(id: "e"))
        XCTAssertFalse(original.canInsertEdgeMidpoint(id: "missing"))
        XCTAssertEqual(original.encoded(), bytes)
        for state in ["locked='true'", "visible='false'", "disabled='true'"] {
            XCTAssertFalse(try document(state: state).canInsertEdgeMidpoint(id: "e"))
        }
        for transform: (String) -> String in [
            { $0.replacingOccurrences(of: "to='b'", with: "to='a'") },
            { $0.replacingOccurrences(of: "id='e' partId='p'", with: "id='e' partId='other'") },
            { $0.replacingOccurrences(of: "partId='p'", with: "") },
            { $0.replacingOccurrences(of: "x='-2'", with: "x='nan'") },
            {
                $0.replacingOccurrences(of: "id='b' partId='p'", with: "id='b' partId='other'")
                    .replacingOccurrences(of: "<parts>", with: "<parts><part id='other'/>")
            },
        ] {
            XCTAssertFalse(try document(transform: transform).canInsertEdgeMidpoint(id: "e"))
        }
    }

}
