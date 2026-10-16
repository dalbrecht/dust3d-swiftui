import Dust3DDocument
import Foundation
import XCTest

final class ComponentHierarchyTests: XCTestCase {
    private func document(
        _ components: String =
            "<component id='group' name='Assembly' future='kept'><future/><component id='leaf' name='Body' linkDataType='partId' linkData='p'/><component id='opaque' linkDataType='futureKind' linkData='payload'/></component><component id='last'/>",
        nodes: String = ""
    ) throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='root'><nodes>\(nodes)</nodes><parts><part id='p' name='Legacy'/></parts><components>\(components)</components></canvas>"
                .utf8)
        let header =
            "<ds3 future='archive'><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testComponentRenamePreservesIndependentlyUnsupportedGraph() throws {
        let original = try document(nodes: "<node id='broken' future='preserved'/>")
        XCTAssertThrowsError(try original.editorContents())
        XCTAssertEqual(try original.components().first?.id, "group")
        let renamed = try original.applying(.setComponentName(id: "group", name: "Changed"))
        XCTAssertEqual(try renamed.components().first?.name, "Changed")
        XCTAssertThrowsError(try renamed.editorContents())
        XCTAssertEqual(renamed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        let xml = try XMLDocument(data: renamed.modelXML)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//node[@id='broken']").first as? XMLElement)?.attribute(forName: "future")?
                .stringValue, "preserved")
    }

    func testComponentsExposePreorderParentageChildOrderAndOpaqueLinksWithoutChangingBytes() throws {
        let original = try document()
        let components = try original.components()
        XCTAssertEqual(components.map(\.id), ["group", "leaf", "opaque", "last"])
        XCTAssertEqual(components.map(\.parentID), [nil, "group", "group", nil])
        XCTAssertEqual(components.map(\.childIDs), [["leaf", "opaque"], [], [], []])
        XCTAssertEqual(components.map(\.name), ["Assembly", "Body", "", ""])
        XCTAssertEqual(components[1].partID, "p")
        XCTAssertNil(components[0].partID)
        XCTAssertNil(components[2].partID)
        XCTAssertEqual(components[2].linkDataType, "futureKind")
        XCTAssertEqual(components[2].linkData, "payload")
        XCTAssertEqual(original.encoded(), try document().encoded())
        XCTAssertTrue(try Dust3DDocument(data: Dust3DDocument.emptyArchive()).components().isEmpty)
    }

    func testRenamePreservesHierarchyPartNameUnknownXMLAssetsAndExactHistory() throws {
        let original = try document()
        let changed = try original.applying(.setComponentName(id: "group", name: "  Head & <body> 🦊  "))
        XCTAssertEqual(try changed.components().first?.name, "Head & <body> 🦊")
        XCTAssertEqual(try changed.components().map(\.childIDs), try original.components().map(\.childIDs))
        XCTAssertEqual(try changed.editorContents().parts.first?.name, "Legacy")
        XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        let xml = try XMLDocument(data: changed.modelXML)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//component[@id='group']").first as? XMLElement)?.attribute(forName: "future")?
                .stringValue, "kept")
        XCTAssertNotNil(try xml.nodes(forXPath: "//component[@id='group']/future").first)
        XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).components(), try changed.components())
        var history = DocumentHistory(document: original)
        try history.apply(.setComponentName(id: "group", name: "Changed"))
        let applied = history.document.encoded()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), applied)
        let cleared = try changed.applying(.setComponentName(id: "group", name: " "))
        XCTAssertEqual(try cleared.components().first?.name, "")
        XCTAssertEqual(try cleared.applying(.setComponentName(id: "group", name: "")).encoded(), cleared.encoded())
        XCTAssertEqual(
            try original.applying(.setComponentName(id: "group", name: " Assembly ")).encoded(), original.encoded())
        try history.beginTransaction()
        try history.apply(.setComponentName(id: "group", name: "Temporary"))
        try history.apply(.setComponentName(id: "group", name: "Changed"))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), applied)
    }

    func testInvalidNamesAndAmbiguousHierarchyRejectWithoutMutation() throws {
        let original = try document()
        XCTAssertNoThrow(try original.applying(.setComponentName(id: "leaf", name: String(repeating: "é", count: 512))))
        for name in [
            String(repeating: "é", count: 513), "bad\0name", "bad\u{007F}name", "bad\u{009F}name", "bad\nname",
            "bad\u{2028}name", "bad\u{FFFF}",
        ] {
            XCTAssertThrowsError(try original.applying(.setComponentName(id: "leaf", name: name))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentName)
            }
        }
        XCTAssertThrowsError(try original.applying(.setComponentName(id: "missing", name: "Name"))) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
        }
        for components in [
            "<future id='unsupported'/>", "<component id='parent'><future id='unsupported'/></component>",
            "<component/>", "<component id=''/>", "<component id='same'><component id='same'/></component>",
        ] {
            let malformed = try document(components)
            XCTAssertThrowsError(try malformed.components()) { XCTAssertEqual($0 as? DocumentError, .invalidComponent) }
            XCTAssertThrowsError(try malformed.applying(.setComponentName(id: "same", name: "Name")))
            XCTAssertEqual(malformed.encoded(), try document(components).encoded())
        }
        let duplicateContainers = try Dust3DDocument(
            snapshotXML: Data("<canvas><nodes/><components/><components/></canvas>".utf8))
        XCTAssertThrowsError(try duplicateContainers.components())
        let excessive = try document((0...10_000).map { "<component id='c\($0)'/>" }.joined())
        XCTAssertThrowsError(try excessive.components()) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
        XCTAssertEqual(original.encoded(), try document().encoded())
    }
}
