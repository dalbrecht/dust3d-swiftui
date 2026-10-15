import Dust3DDocument
import Foundation
import XCTest

final class DocumentOriginTests: XCTestCase {
    private func archive(origin: String) throws -> Dust3DDocument {
        let model = Data(
            "<canvas \(origin) future='root'><nodes><node id='a' partId='p' x='0' y='.5' z='1' radius='.1' future='node'/></nodes><parts><part id='p'/></parts><components><component id='c' name='Keep' linkData='p' linkDataType='partId'/></components><future/></canvas>"
                .utf8)
        let header =
            "<ds3 future='header'><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque' offset='\(model.count)' size='4' future='asset'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testReadingValidOriginAndSemanticNoOpPreservesAllBytes() throws {
        let original = try archive(origin: "originX='5e-1' originY='-0.5' originZ='0'")
        let position = NodePosition(x: 0.5, y: -0.5, z: 0)
        XCTAssertEqual(try original.origin(), position)
        XCTAssertEqual(try original.applying(.setOrigin(position)).encoded(), original.encoded())
    }

    func testMissingPartialMalformedAndOversizedOriginsAreUnavailableButPreserved() throws {
        for attributes in [
            "", "originX='.5'", "originX='bad' originY='0' originZ='1'", "originX='nan' originY='0' originZ='1'",
            "originX='inf' originY='0' originZ='1'", "originX='1000001' originY='0' originZ='1'",
        ] {
            let original = try archive(origin: attributes)
            XCTAssertNil(try original.origin())
            XCTAssertEqual(try Dust3DDocument(data: original.encoded()).encoded(), original.encoded())
            let repaired = try original.applying(.setOrigin(.init(x: 0.5, y: 0.5, z: 1)))
            XCTAssertEqual(try repaired.origin(), .init(x: 0.5, y: 0.5, z: 1))
            XCTAssertEqual(repaired.asset(named: "opaque"), original.asset(named: "opaque"))
        }
    }

    func testOriginEditPreservesGraphExtensionsAssetsAndExactUndoRedo() throws {
        let original = try archive(origin: "originX='.5' originY='.5' originZ='1'")
        var history = DocumentHistory(document: original)
        try history.apply(.setOrigin(.init(x: -1_000_000, y: 0, z: 1_000_000)))
        let edited = history.document
        XCTAssertEqual(try edited.origin(), .init(x: -1_000_000, y: 0, z: 1_000_000))
        XCTAssertEqual(try edited.node(id: "a"), try original.node(id: "a"))
        XCTAssertEqual(edited.asset(named: "opaque"), Data([0, 255, 10, 128]))
        let before = try XMLDocument(data: original.modelXML)
        let after = try XMLDocument(data: edited.modelXML)
        for path in ["/canvas/nodes", "/canvas/parts", "/canvas/components", "/canvas/future"] {
            XCTAssertEqual(
                try before.nodes(forXPath: path).first?.xmlString, try after.nodes(forXPath: path).first?.xmlString)
        }
        XCTAssertEqual(after.rootElement()?.attribute(forName: "future")?.stringValue, "root")
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited.encoded())
    }

    func testInvalidCoordinatesRejectAtomicallyAndPreserveRedo() throws {
        let original = try archive(origin: "originX='.5' originY='.5' originZ='1'")
        var history = DocumentHistory(document: original)
        try history.apply(.setOrigin(.init(x: 1, y: 2, z: 3)))
        XCTAssertTrue(history.undo())
        for value in [Double.nan, .infinity, -.infinity, 1_000_001, -1_000_001] {
            for position in [
                NodePosition(x: value, y: 0, z: 0), .init(x: 0, y: value, z: 0), .init(x: 0, y: 0, z: value),
            ] {
                XCTAssertThrowsError(try history.apply(.setOrigin(position))) {
                    XCTAssertEqual($0 as? DocumentError, .invalidOrigin)
                }
                XCTAssertEqual(history.document.encoded(), original.encoded())
                XCTAssertTrue(history.canRedo)
                XCTAssertFalse(history.canUndo)
            }
        }
    }

    func testNetZeroOriginTransactionsPreserveOriginalSpellingsAndRedo() throws {
        let original = try archive(origin: "originX='5e-1' originY='0.50' originZ='1e0'")
        var history = DocumentHistory(document: original)
        try history.apply(.setOrigin(.init(x: 1, y: 2, z: 3)))
        XCTAssertTrue(history.undo())
        try history.beginTransaction()
        try history.apply(.setOrigin(.init(x: -0.5, y: -0.5, z: -1)))
        try history.apply(.setOrigin(.init(x: 0.5, y: 0.5, z: 1)))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
    }
}
