import Dust3DDocument
import Foundation
import XCTest

final class PartSplittingTests: XCTestCase {
    private func document(disconnected: Bool = false, locked: Bool = false, components: Bool = true) throws
        -> Dust3DDocument
    {
        let xml = """
            <canvas><nodes>
            <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
            <node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
            <node id='c' partId='p' x='2' y='0' z='0' radius='.1'/>
            <node id='d' partId='p' x='3' y='0' z='0' radius='.1'/>
            <node id='e' partId='q' x='4' y='0' z='0' radius='.1'/>
            </nodes><edges><edge id='ab' from='a' to='b' partId='p'/>
            \(disconnected ? "" : "<edge id='bc' from='b' to='c' partId='p'/>")
            <edge id='cd' from='c' to='d' future='edge'/></edges>
            <parts><part id='p' name='Chain' locked='\(locked)' deformWidth='1.2' future='part'><future/></part>
            <part id='q' cutFaceLinkedId='p'/></parts>
            \(components ? "<components><component id='group'><component id='leaf' linkData='p' linkDataType='partId' color='#ff123456' future='style'><future/><component id='child' linkData='q' linkDataType='partId'/></component><component id='after'/></component><component id='other' linkData='p' linkDataType='partId'/></components>" : "")
            </canvas>
            """
        return try archive(xml)
    }

    private func archive(_ xml: String) throws -> Dust3DDocument {
        let model = Data(xml.utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='2'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255]))
    }

    func testRequirementsAndSplitPreserveMetadataHierarchyAndLinks() throws {
        let original = try document()
        XCTAssertTrue(try original.partSplitRequirements(for: ["p"]).isEmpty)
        let disconnected = try original.applying(.removeEdge(id: "bc"))
        let requirement = try XCTUnwrap(try disconnected.partSplitRequirements(for: ["p"]).first)
        XCTAssertEqual(requirement.partID, "p")
        XCTAssertEqual(requirement.additionalPartCount, 1)
        XCTAssertEqual(requirement.componentsPerPart, 2)
        let split = try disconnected.applying(
            .splitPart(id: "p", identities: [.init(partID: "new", componentIDs: ["newleaf", "newother"])]))
        let contents = try split.editorContents()
        XCTAssertEqual(contents.nodes.map(\.partID), ["p", "p", "new", "new", "q"])
        let xml = try XMLDocument(data: split.modelXML)
        let copiedPart = try XCTUnwrap(try xml.nodes(forXPath: "//part[@id='new']").first as? XMLElement)
        XCTAssertEqual(copiedPart.attribute(forName: "future")?.stringValue, "part")
        XCTAssertEqual(copiedPart.attribute(forName: "deformWidth")?.stringValue, "1.2")
        XCTAssertEqual(copiedPart.elements(forName: "future").count, 1)
        let copy = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='newleaf']").first as? XMLElement)
        XCTAssertEqual(copy.attribute(forName: "linkData")?.stringValue, "new")
        XCTAssertEqual(copy.attribute(forName: "future")?.stringValue, "style")
        XCTAssertEqual(copy.attribute(forName: "color")?.stringValue, "#ff123456")
        XCTAssertEqual(copy.elements(forName: "future").count, 1)
        XCTAssertTrue(copy.elements(forName: "component").isEmpty)
        let group = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='group']").first as? XMLElement)
        XCTAssertEqual(
            group.elements(forName: "component").compactMap { $0.attribute(forName: "id")?.stringValue },
            ["leaf", "newleaf", "after"])
        XCTAssertEqual(try xml.nodes(forXPath: "//component[@id='child']").count, 1)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//part[@id='q']").first as? XMLElement)?.attribute(forName: "cutFaceLinkedId")?
                .stringValue, "p")
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//edge[@id='cd']").first as? XMLElement)?.attribute(forName: "partId")?
                .stringValue, "new")
        XCTAssertEqual(split.asset(named: "opaque"), Data([0, 255]))
        var history = DocumentHistory(document: original)
        try history.beginTransaction()
        try history.apply(.removeEdge(id: "bc"))
        try history.apply(
            .splitPart(id: "p", identities: [.init(partID: "new", componentIDs: ["newleaf", "newother"])]))
        try history.endTransaction()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), split.encoded())
    }

    func testPlansRejectInvalidIdentitiesAndReadOnlySources() throws {
        let source = try document(disconnected: true)
        for identities: [PartSplitIdentity] in [
            [], [.init(partID: "new", componentIDs: [])], [.init(partID: "p", componentIDs: ["x", "y"])],
            [.init(partID: "new", componentIDs: ["x", "x"])], [.init(partID: "", componentIDs: ["x", "y"])],
            [.init(partID: "new", componentIDs: ["leaf", "y"])],
        ] {
            XCTAssertThrowsError(try source.applying(.splitPart(id: "p", identities: identities)))
        }
        XCTAssertThrowsError(try source.partSplitRequirements(for: ["missing"]))
        XCTAssertThrowsError(try document(disconnected: true, locked: true).partSplitRequirements(for: ["p"]))
        XCTAssertThrowsError(try source.applying(.splitPart(id: "missing", identities: [])))
        let connected = try document()
        XCTAssertEqual(try connected.applying(.splitPart(id: "p", identities: [])).encoded(), connected.encoded())
        XCTAssertThrowsError(
            try connected.applying(.splitPart(id: "p", identities: [.init(partID: "new", componentIDs: ["x", "y"])])))
        XCTAssertTrue(try source.partSplitRequirements(for: []).isEmpty)
    }

    func testLargestGroupRetainsIdentityAndUnlinkedPartsStayUnlinked() throws {
        let original = try document(components: false)
        let disconnected = try original.applying(.removeEdge(id: "ab"))
        let requirement = try XCTUnwrap(try disconnected.partSplitRequirements(for: ["p"]).first)
        XCTAssertEqual(requirement.componentsPerPart, 0)
        let split = try disconnected.applying(.splitPart(id: "p", identities: [.init(partID: "new", componentIDs: [])]))
        XCTAssertEqual(try split.editorContents().nodes.map(\.partID), ["new", "p", "p", "p", "q"])
        XCTAssertTrue(try XMLDocument(data: split.modelXML).nodes(forXPath: "//component").isEmpty)
    }
    func testComponentCopyLimitsAndInvalidReferenceIdentitiesAreRejected() throws {
        let nodes =
            "<nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p' x='1' y='0' z='0' radius='.1'/></nodes><parts><part id='p'/></parts>"
        let components = (0..<10_000).map { "<component id='c\($0)' linkData='p' linkDataType='partId'/>" }.joined()
        for namespace in ["", " xmlns='urn:future'"] {
            let source = try archive("<canvas\(namespace)>\(nodes)<components>\(components)</components></canvas>")
            XCTAssertThrowsError(try source.partSplitRequirements(for: ["p"])) {
                XCTAssertEqual($0 as? DocumentError, .limitExceeded)
            }
        }
        for components in [
            "<component linkData='p' linkDataType='partId'/>",
            "<component id='same' linkData='p' linkDataType='partId'/><component id='same' linkData='p' linkDataType='partId'/>",
        ] {
            let source = try archive("<canvas>\(nodes)<components>\(components)</components></canvas>")
            XCTAssertThrowsError(try source.partSplitRequirements(for: ["p"]))
        }
    }

    func testCyclesMultipleGroupsNamespacesAndEmptyParts() throws {
        let nodes = ["a", "b", "c", "d", "e"].map { "<node id='\($0)' partId='p' x='0' y='0' z='0' radius='.1'/>" }
            .joined()
        let source = try archive(
            "<canvas xmlns='urn:future'><nodes>\(nodes)</nodes><edges><edge id='ab' from='a' to='b'/><edge id='bc' from='b' to='c'/><edge id='ca' from='c' to='a'/></edges><parts><part id='p'/><part id='empty'/></parts><components><component id='comp' linkData='p' linkDataType='partId'/></components></canvas>"
        )
        let plan = try XCTUnwrap(try source.partSplitRequirements(for: ["p"]).first)
        XCTAssertEqual(plan.additionalPartCount, 2)
        let split = try source.applying(
            .splitPart(
                id: "p",
                identities: [.init(partID: "p1", componentIDs: ["c1"]), .init(partID: "p2", componentIDs: ["c2"])]))
        XCTAssertEqual(try split.editorContents().nodes.map(\.partID), ["p", "p", "p", "p1", "p2"])
        let xml = try XMLDocument(data: split.modelXML)
        XCTAssertEqual(xml.rootElement()?.uri, "urn:future")
        XCTAssertEqual(
            try xml.nodes(forXPath: "//component").compactMap {
                ($0 as? XMLElement)?.attribute(forName: "id")?.stringValue
            }, ["comp", "c1", "c2"])
        XCTAssertTrue(try source.partSplitRequirements(for: ["empty"]).isEmpty)
        XCTAssertEqual(try source.applying(.splitPart(id: "empty", identities: [])).encoded(), source.encoded())
    }

    func testCrossPartEdgesCannotBeSilentlyReinterpreted() throws {
        let source = try document(disconnected: true)
        let xml = String(decoding: source.modelXML, as: UTF8.self).replacingOccurrences(
            of: "to=\"d\"", with: "to=\"e\""
        ).replacingOccurrences(of: "to='d'", with: "to='e'")
        let crossed = try archive(xml)
        XCTAssertThrowsError(try crossed.partSplitRequirements(for: ["p"]))
    }

    func testCopiedMetadataBudgetAndLongIdentifiersAreRejectedBeforePublication() throws {
        let source = try document(disconnected: true)
        XCTAssertThrowsError(
            try source.applying(
                .splitPart(
                    id: "p",
                    identities: [.init(partID: String(repeating: "x", count: 129), componentIDs: ["one", "two"])])))
        let payload = String(repeating: "x", count: 6 * 1024 * 1024)
        let nodes = ["a", "b", "c"].map { "<node id='\($0)' partId='p' x='0' y='0' z='0' radius='.1'/>" }.joined()
        let large = try archive(
            "<canvas><nodes>\(nodes)</nodes><parts><part id='p'><future>\(payload)</future></part></parts></canvas>")
        XCTAssertThrowsError(try large.partSplitRequirements(for: ["p"])) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
    }

    func testComponentNamespaceAttributesAndCommentsSurviveStyleCopy() throws {
        let xml =
            "<canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p' x='1' y='0' z='0' radius='.1'/></nodes><parts><part id='p'/></parts><components><component id='style' linkData='p' linkDataType='partId' xmlns:m='urn:metadata' m:value='retain'><!--note--><future/></component></components></canvas>"
        let source = try archive(xml)
        let split = try source.applying(.splitPart(id: "p", identities: [.init(partID: "new", componentIDs: ["copy"])]))
        let document = try XMLDocument(data: split.modelXML)
        let copy = try XCTUnwrap(try document.nodes(forXPath: "//component[@id='copy']").first as? XMLElement)
        XCTAssertEqual(copy.attribute(forName: "m:value")?.stringValue, "retain")
        XCTAssertEqual(copy.namespaces?.first?.stringValue, "urn:metadata")
        XCTAssertTrue(copy.children?.contains { $0.kind == .comment && $0.stringValue == "note" } == true)
    }

    func testPartCountLimitRejectsAdditionalGroups() throws {
        let parts = (0..<10_000).map { "<part id='p\($0)'/>" }.joined()
        let source = try archive(
            "<canvas><nodes><node id='a' partId='p0' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p0' x='1' y='0' z='0' radius='.1'/></nodes><parts>\(parts)</parts></canvas>"
        )
        XCTAssertThrowsError(try source.partSplitRequirements(for: ["p0"])) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
    }

    func testExtensionComponentsAreIgnoredAndRetainedWithoutMutation() throws {
        let original = try document(disconnected: true)
        let root = try XMLDocument(data: original.modelXML)
        let extensionElement = try XMLElement(
            xmlString:
                "<future><component linkData='p' linkDataType='partId'/><component id='extension' linkData='p' linkDataType='partId'/></future>"
        )
        root.rootElement()?.addChild(extensionElement)
        root.rootElement()?.elements(forName: "components").first?.addChild(
            try XMLElement(xmlString: "<future><component linkData='p' linkDataType='partId'/></future>"))
        let source = try archive(root.xmlString(options: [.nodePreserveAll]))
        let requirement = try XCTUnwrap(try source.partSplitRequirements(for: ["p"]).first)
        XCTAssertEqual(requirement.componentsPerPart, 2)
        let before = extensionElement.xmlString(options: [.nodePreserveAll])
        let split = try source.applying(
            .splitPart(id: "p", identities: [.init(partID: "new", componentIDs: ["newleaf", "newother"])]))
        let result = try XMLDocument(data: split.modelXML)
        XCTAssertEqual(
            result.rootElement()?.elements(forName: "future").first?.xmlString(options: [.nodePreserveAll]), before)
        XCTAssertEqual(
            result.rootElement()?.elements(forName: "components").first?.elements(forName: "future").count, 1)
        XCTAssertEqual(try split.editorContents().nodes.map(\.partID), ["p", "p", "new", "new", "q"])
    }

    func testOpaqueComponentTagsDoNotConsumeNativeCreationLimit() throws {
        let opaque = (0..<10_000).map { "<component id='extension\($0)'/>" }.joined()
        let source = try archive("<canvas><future>\(opaque)</future></canvas>")
        let created = try source.applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let model = try XMLDocument(data: created.modelXML)
        XCTAssertEqual(
            model.rootElement()?.elements(forName: "future").first?.elements(forName: "component").count, 10_000)
        XCTAssertEqual(
            model.rootElement()?.elements(forName: "components").first?.elements(forName: "component").count, 1)
    }

}
