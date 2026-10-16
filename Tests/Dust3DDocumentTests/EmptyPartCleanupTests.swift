import Foundation
import XCTest

@testable import Dust3DDocument

final class EmptyPartCleanupTests: XCTestCase {
    private let profile = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private func document(templateFlags: String = "") throws -> Dust3DDocument {
        let model = Data(
            "<canvas originX='.5' originY='.5' originZ='1' future='keep'><nodes><node id='a' partId='\(profile)' x='0' y='0' z='0' radius='.1'/><node id='b' partId='q' x='1' y='0' z='0' radius='.1' cutFace='\(profile)'/><node id='c' partId='q' x='2' y='0' z='0' radius='.1' cutFace='Quad'/><node id='d' partId='q' x='3' y='0' z='0' radius='.1' cutFace='plain'/></nodes><parts><part id='\(profile)' name='Profile'/><part id='q' cutFace='\(profile)' future='part'/><part id='template' \(templateFlags)/><part id='plain'/></parts><components><component id='group' future='group'><component id='leaf' linkDataType='partId' linkData='\(profile)'/><component id='nested' linkDataType='partId' linkData='\(profile)' future='nested'><component id='survivor' linkDataType='partId' linkData='q'/></component><component id='unknown' linkDataType='partId' linkData='\(profile)'><future value='keep'/></component><component id='template-component' linkDataType='partId' linkData='template'/></component></components><future value='root'/></canvas>"
                .utf8)
        let asset = Data([0, 255, 17, 42])
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='future.bin' offset='\(model.count)' size='\(asset.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + asset)
    }

    func testCleanupRemovesOnlyRequestedEmptyPartsAndPreservesNestedContentAndAssets() throws {
        let original = try document()
        let emptied = try original.applying(.removeNode(id: "a"))
        let cleaned = try emptied.applying(.pruneEmptyParts([profile]))
        XCTAssertEqual(try cleaned.editorContents().parts.map(\.id), ["q", "template", "plain"])
        let xml = try XMLDocument(data: cleaned.modelXML)
        func elements(_ path: String) throws -> [XMLNode] { try xml.nodes(forXPath: path) }
        XCTAssertTrue(try elements("//component[@id='leaf']").isEmpty)
        XCTAssertEqual(try elements("//component[@id='group']/component").count, 3)
        XCTAssertTrue(try elements("//component[@id='nested']/@linkData").isEmpty)
        XCTAssertTrue(try elements("//component[@id='nested']/@linkDataType").isEmpty)
        XCTAssertEqual(try elements("//component[@id='nested']/@future").first?.stringValue, "nested")
        XCTAssertEqual(try elements("//component[@id='nested']/component/@id").first?.stringValue, "survivor")
        XCTAssertTrue(try elements("//component[@id='unknown']/@linkData").isEmpty)
        XCTAssertEqual(try elements("//component[@id='unknown']/future/@value").first?.stringValue, "keep")
        XCTAssertTrue(try elements("//node[@id='b']/@cutFace").isEmpty)
        XCTAssertTrue(try elements("//part[@id='q']/@cutFace").isEmpty)
        XCTAssertEqual(try elements("//node[@id='c']/@cutFace").first?.stringValue, "Quad")
        XCTAssertEqual(try elements("//node[@id='d']/@cutFace").first?.stringValue, "plain")
        XCTAssertEqual(try elements("//canvas/@future").first?.stringValue, "keep")
        XCTAssertEqual(try elements("//part[@id='q']/@future").first?.stringValue, "part")
        XCTAssertEqual(cleaned.encoded().suffix(4), Data([0, 255, 17, 42]))
        let reopened = try Dust3DDocument(data: cleaned.encoded())
        XCTAssertEqual(try reopened.editorContents().parts, try cleaned.editorContents().parts)
        var history = DocumentHistory(document: original)
        try history.beginTransaction()
        try history.apply(.removeNode(id: "a"))
        try history.apply(.pruneEmptyParts([profile]))
        try history.endTransaction()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), cleaned.encoded())
    }

    func testFormattingWhitespaceDoesNotRetainLeafButMeaningfulTextAndCommentsSurvive() throws {
        let model = Data(
            "<canvas><parts><part id='empty'/></parts><components><component id='leaf' xml:space='preserve' linkDataType='partId' linkData='empty'>\n  \t</component><component id='text' linkDataType='partId' linkData='empty'> meaningful text </component><component id='comment' linkDataType='partId' linkData='empty'><!--keep--></component></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let data =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        let original = try Dust3DDocument(data: data)
        let xml = try XMLDocument(data: original.modelXML, options: [.nodePreserveAll])
        let leaf = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='leaf']").first as? XMLElement)
        // Foundation versions differ in blank-text parsing; exercise a preserved-whitespace DOM explicitly.
        let whitespace = XMLNode(kind: .text)
        whitespace.stringValue = "\n  \t"
        leaf.addChild(whitespace)
        XCTAssertGreaterThan(leaf.childCount, 0)
        try EmptyPartCleanup.apply(["empty"], model: xml, contents: original.editorContents())
        XCTAssertTrue(try xml.nodes(forXPath: "//component[@id='leaf']").isEmpty)
        XCTAssertEqual(try xml.nodes(forXPath: "//component/@id").compactMap(\.stringValue), ["text", "comment"])
        XCTAssertEqual(
            try xml.nodes(forXPath: "//component[@id='text']/text()").first?.stringValue, " meaningful text ")
        XCTAssertEqual(try xml.nodes(forXPath: "//component[@id='comment']/comment()").first?.stringValue, "keep")
        XCTAssertTrue(try xml.nodes(forXPath: "//component/@linkData").isEmpty)
    }

    func testStandaloneEmptyTemplatePreservesMissingNodeContainerAndIncompleteReferences() throws {
        let model = Data(
            "<canvas><parts><part id='empty'/><part id='other'/></parts><components><component id='incomplete' linkDataType='partId'/><component id='future' linkDataType='futureId' linkData='empty'/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let data =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        let original = try Dust3DDocument(data: data)
        let cleaned = try original.applying(.pruneEmptyParts(["empty"]))
        XCTAssertEqual(try cleaned.editorContents().parts.map(\.id), ["other"])
        let xml = try XMLDocument(data: cleaned.modelXML)
        XCTAssertTrue(try xml.nodes(forXPath: "/canvas/nodes").isEmpty)
        XCTAssertEqual(try xml.nodes(forXPath: "//component/@id").compactMap(\.stringValue), ["incomplete", "future"])
        XCTAssertEqual(try xml.nodes(forXPath: "//component[@id='future']/@linkData").first?.stringValue, "empty")
    }

    func testInvalidNonemptyDuplicateMissingAndReadonlyTargetsRejectAtomically() throws {
        let original = try document()
        for targets in [[profile], ["missing"], ["template", "template"]] {
            XCTAssertThrowsError(try original.applying(.pruneEmptyParts(targets))) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
        }
        for flags in ["locked='true'", "visible='false'", "disabled='true'"] {
            let readonly = try document(templateFlags: flags)
            XCTAssertThrowsError(try readonly.applying(.pruneEmptyParts(["template"]))) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
        }
        XCTAssertEqual(try original.applying(.pruneEmptyParts([])).encoded(), original.encoded())
        let explicit = try original.applying(.pruneEmptyParts(["template", "plain"]))
        XCTAssertEqual(try explicit.editorContents().parts.map(\.id), [profile, "q"])
        XCTAssertEqual(try explicit.editorContents().nodes.last?.value, try original.editorContents().nodes.last?.value)
        XCTAssertTrue(String(decoding: explicit.modelXML, as: UTF8.self).contains("cutFace='plain'"))
    }
}
