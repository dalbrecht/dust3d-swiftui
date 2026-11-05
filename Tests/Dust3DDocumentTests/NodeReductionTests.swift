import Foundation
import XCTest

@testable import Dust3DDocument

final class NodeReductionTests: XCTestCase {
    private let a = "{00000000-0000-4000-8000-000000000001}"
    private let b = "{00000000-0000-4000-8000-000000000002}"
    private let c = "{00000000-0000-4000-8000-000000000003}"
    private let d = "{00000000-0000-4000-8000-000000000004}"

    private func chain(_ edges: [(String, String, String)], state: String = "") throws -> Dust3DDocument {
        let nodes = [a, b, c, d].map { "<node id='\($0)' partId='p' x='1' y='2' z='3' radius='4' future='node'/>" }
            .joined()
        let links = edges.map {
            "<edge id='\($0.0)' from='\($0.1)' to='\($0.2)' partId='p' name='\($0.0)' boneName='Bone\($0.0)' future='\($0.0)'><extension/></edge>"
        }.joined()
        return try Dust3DDocument(
            snapshotXML: Data(
                "<canvas future='canvas'><nodes>\(nodes)</nodes><edges>\(links)</edges><parts><part id='p' \(state)/></parts><components><component id='component' linkData='p' linkDataType='partId'/></components></canvas>"
                    .utf8))
    }

    func testRawEdgeLoadOrderAndSequentialNeighborReplacementRetainCorrectMetadata() throws {
        let original = try chain([("2BC", b, c), ("1CD", c, d), ("0AB", a, b)])
        for ids in [[b, c], [c, b]] {
            XCTAssertTrue(original.canReduceNodes(ids))
            let result = try original.applying(.reduceNodes(ids))
            let contents = try result.editorContents()
            XCTAssertEqual(contents.nodes.map(\.id), [a, d])
            XCTAssertEqual(contents.edges.map(\.id), ["1CD"])
            XCTAssertEqual(contents.edges.first?.fromID, a)
            XCTAssertEqual(contents.edges.first?.toID, d)
            let xml = try XMLDocument(data: result.modelXML)
            let edge = try XCTUnwrap(xml.nodes(forXPath: "/canvas/edges/edge").first as? XMLElement)
            XCTAssertEqual(edge.attribute(forName: "future")?.stringValue, "1CD")
            XCTAssertEqual(edge.attribute(forName: "name")?.stringValue, "1CD")
            XCTAssertEqual(edge.elements(forName: "extension").count, 1)
            XCTAssertEqual(
                contents.nodes.map(\.value),
                try original.editorContents().nodes.filter { [a, d].contains($0.id) }.map(\.value))
        }
    }

    func testMixedSelectionSkipsEndpointsAndNoopPreservesBytesHistoryAndRedo() throws {
        let original = try chain([("AB", a, b), ("BC", b, c), ("CD", c, d)])
        XCTAssertFalse(original.canReduceNodes([a, d]))
        XCTAssertTrue(original.canReduceNodes([a, b, d]))
        XCTAssertEqual(try original.applying(.reduceNodes([a, d])).encoded(), original.encoded())
        var history = DocumentHistory(document: original)
        let preview = history.previewIdentity
        try history.apply(.reduceNodes([a, b, d]))
        let reduced = history.document.encoded()
        XCTAssertNotEqual(history.previewIdentity, preview)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        try history.apply(.reduceNodes([a, d]))
        XCTAssertTrue(history.canRedo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), reduced)
    }

    func testMidpointLiveOrderDiffersFromReloadAndUndoRestoresFutureReduction() throws {
        let original = try chain([("a", a, b), ("b", b, c), ("c", c, d)])
        var history = DocumentHistory(document: original)
        try history.apply(.insertEdgeMidpoint(id: "b", nodeID: "middle", edgeID: "z"))
        let live = history.document
        let reloaded = try Dust3DDocument(data: live.encoded())
        let liveResult = try live.applying(.reduceNodes([c]))
        let reloadedResult = try reloaded.applying(.reduceNodes([c]))
        XCTAssertEqual(try liveResult.editorContents().edges.map(\.id), ["a", "b", "z"])
        XCTAssertEqual(try reloadedResult.editorContents().edges.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(try liveResult.editorContents().edges.first(where: { $0.id == "z" })?.toID, d)
        XCTAssertTrue(history.undo())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(try history.document.applying(.reduceNodes([c])).encoded(), liveResult.encoded())
    }
    func testOppositeSelectedUUIDOrderChangesWhichMetadataSurvives() throws {
        let original = try chain([("2BC", c, b), ("1CD", b, d), ("0AB", a, c)])
        let reduced = try original.applying(.reduceNodes([c, b]))
        XCTAssertEqual(try reduced.editorContents().edges.map(\.id), ["0AB"])
    }

    func testBatchFailureAfterEarlierReductionIsAtomicAndReadOnlyBatchIsUnavailable() throws {
        let original = try chain([("0AB", a, b), ("2BC", b, c), ("1CD", c, d)])
        let model = try XMLDocument(data: original.modelXML)
        let edge = try XCTUnwrap(model.nodes(forXPath: "/canvas/edges/edge[@id='1CD']").first as? XMLElement)
        edge.attribute(forName: "partId")?.stringValue = "wrong"
        let invalid = try Dust3DDocument(snapshotXML: model.xmlData())
        var history = DocumentHistory(document: invalid)
        let preview = history.previewIdentity
        XCTAssertFalse(invalid.canReduceNodes([b, c]))
        XCTAssertThrowsError(try history.apply(.reduceNodes([b, c])))
        XCTAssertEqual(history.document.encoded(), invalid.encoded())
        XCTAssertEqual(history.previewIdentity, preview)
        XCTAssertFalse(history.canUndo)
        for state in ["locked='true'", "visible='false'", "disabled='true'"] {
            let readonly = try chain([("0AB", a, b), ("2BC", b, c), ("1CD", c, d)], state: state)
            XCTAssertFalse(readonly.canReduceNodes([b, c]))
            XCTAssertThrowsError(try readonly.applying(.reduceNodes([b, c])))
            XCTAssertEqual(try readonly.applying(.reduceNodes([a, d])).encoded(), readonly.encoded())
        }
    }

    func testReductionRejectsParallelEdgesInOriginalAndEvolvingLoops() throws {
        let triangle = try chain([("AB", a, b), ("BC", b, c), ("CA", c, a)])
        let square = try chain([("AB", a, b), ("BC", b, c), ("CD", c, d), ("DA", d, a)])
        XCTAssertTrue(square.canReduceNodes([b]))
        for (document, selection) in [(triangle, [b]), (square, [b, c])] {
            var history = DocumentHistory(document: document)
            XCTAssertFalse(document.canReduceNodes(selection))
            XCTAssertThrowsError(try history.apply(.reduceNodes(selection))) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
            XCTAssertEqual(history.document.encoded(), document.encoded())
            XCTAssertFalse(history.canUndo)
        }
    }

    func testMetadataAssetsCopyAndPastePreserveLiveOrderAndPasteUsesRawSourceOrder() throws {
        let original = try chain([("a", a, b), ("b", b, c), ("c", c, d)])
        let live = try original.applying(.insertEdgeMidpoint(id: "b", nodeID: "middle", edgeID: "z"))
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3])
        let assetEdited = try live.applying(.setReferenceImagePNG(png))
            .applying(.setPartName(id: "p", name: "Renamed"))
        XCTAssertEqual(try assetEdited.applying(.reduceNodes([c])).editorContents().edges.map(\.id), ["a", "b", "z"])
        let clipboard = try assetEdited.copyingNodes(Set(try assetEdited.editorContents().nodes.map(\.id)))
        let identities = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "copy" + $0) })
        let pasted = try live.applying(
            .pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0, z: 0)))
        XCTAssertEqual(pasted.referenceImagePNG, png)
        let reduced = try pasted.applying(.reduceNodes([c, "copy" + c]))
        let edges = try reduced.editorContents().edges.map(\.id)
        XCTAssertTrue(edges.contains("z"))
        XCTAssertFalse(edges.contains("c"))
        XCTAssertTrue(edges.contains("copyc"))
        XCTAssertFalse(edges.contains("copyz"))
    }

    func testOrderOnlyTransactionIsUndoableWithoutDirtyingOrChangingPreview() throws {
        // Metadata-free edges allow remove/re-add to restore exactly the same persisted model intent.
        let source = try chain([("a", a, b), ("c", c, d), ("b", b, c)])
        let xml = try XMLDocument(data: source.modelXML)
        for edge in try xml.nodes(forXPath: "/canvas/edges/edge").compactMap({ $0 as? XMLElement }) {
            for name in ["name", "boneName", "future"] { edge.removeAttribute(forName: name) }
            edge.setChildren([])
            let attributes = ["id", "partId", "from", "to"].compactMap { edge.attribute(forName: $0) }
            for attribute in attributes { attribute.detach() }
            for attribute in attributes { edge.addAttribute(attribute) }
        }
        let rawModel = Data(
            String(decoding: xml.xmlData(), as: UTF8.self).replacingOccurrences(of: "\"", with: "'").utf8)
        let rawHeader = "<ds3 custom='preserved'><model name='model.xml' offset='0' size='\(rawModel.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let offset = prefix.count + 11 + rawHeader.utf8.count
        let original = try Dust3DDocument(
            data: Data("\(prefix)\(String(format: "%010d", offset))\n\(rawHeader)".utf8) + rawModel)
        var history = DocumentHistory(document: original)
        let preview = history.previewIdentity
        try history.beginTransaction()
        try history.apply(.removeEdge(id: "b"))
        try history.apply(.addEdge(id: "b", from: b, to: c))
        try history.endTransaction()
        XCTAssertTrue(history.canUndo)
        XCTAssertEqual(history.previewIdentity, preview)
        XCTAssertFalse(history.isDirty)
        XCTAssertFalse(history.document.hasSameEditingState(as: original))
        XCTAssertEqual(try history.document.applying(.reduceNodes([c])).editorContents().edges.map(\.id), ["a", "c"])
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertEqual(try history.document.applying(.reduceNodes([c])).editorContents().edges.map(\.id), ["a", "b"])
        XCTAssertTrue(history.redo())
        XCTAssertEqual(try history.document.applying(.reduceNodes([c])).editorContents().edges.map(\.id), ["a", "c"])
    }

    func testDegreeThreeSelectionSkipsAndHistoryBudgetChargesAdjacency() throws {
        let source = try chain([("a", a, b), ("b", b, c), ("c", c, d)])
        let branch = try source.applying(.addEdge(id: "branch", from: b, to: d))
        XCTAssertFalse(branch.canReduceNodes([a, b]))
        XCTAssertEqual(try branch.applying(.reduceNodes([a, b])).encoded(), branch.encoded())
        XCTAssertGreaterThan(source.historyByteCost, source.encoded().count)
        var bounded = DocumentHistory(document: source, maximumUndoBytes: source.encoded().count)
        XCTAssertThrowsError(try bounded.apply(.reduceNodes([b])))
        XCTAssertEqual(bounded.document.encoded(), source.encoded())
        XCTAssertFalse(bounded.canUndo)
        var history = DocumentHistory(document: source)
        try history.apply(.reduceNodes([b]))
        history.markSaved(history.document)
        XCTAssertFalse(history.isDirty)
        let reopened = try Dust3DDocument(data: history.document.encoded())
        XCTAssertEqual(try reopened.editorContents().nodes, try history.document.editorContents().nodes)
        XCTAssertEqual(try reopened.editorContents().edges, try history.document.editorContents().edges)
    }

}
