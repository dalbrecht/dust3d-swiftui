import Dust3DDocument
import Foundation
import XCTest

final class ComponentBatchUngroupTests: XCTestCase {
    private func source(_ components: String) throws -> Dust3DDocument {
        let xml = Data(
            "<canvas future='keep'><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' locked='true' disabled='true' visible='false'/></parts><components>\(components)</components><future node='n'/></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/><asset name='opaque.bin' offset='\(xml.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml + Data([0, 255, 10, 128]))
    }
    func testLoadedWrapperKindsMixedLeavesAndOpaquePayloadPromoteAtExactSlotsWithoutGraphCleanup() throws {
        let original = try source(
            "<component id='before'/><component id='a' linkDataType='future' linkData='opaque' future='removed'><component id='x' future='keep'/><!--inside--><ext:payload xmlns:ext='urn:payload' future='retained'/></component><!--between--><component id='b' linkDataType='partId' linkData='p'><component id='y'/></component><component id='partLeaf' linkDataType='partId' linkData='p'/><component id='after' wrapBindTo='a'/>"
        )
        let changed = try original.applying(.ungroupComponents(ids: ["a", "partLeaf", "b"]))
        XCTAssertEqual(try changed.components().map(\.id), ["before", "x", "y", "partLeaf", "after"])
        XCTAssertEqual(try changed.editorContents().nodes, try original.editorContents().nodes)
        XCTAssertEqual(try changed.editorContents().parts, try original.editorContents().parts)
        XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        let xml = String(decoding: changed.modelXML, as: UTF8.self)
        XCTAssertFalse(xml.contains("future='removed'"))
        XCTAssertTrue(xml.contains("future='retained'"))
        XCTAssertTrue(xml.contains("wrapBindTo='a'"))
        let container = try XCTUnwrap(
            XMLDocument(data: changed.modelXML).rootElement()?.elements(forName: "components").first)
        let tokens = (container.children ?? []).map { node in
            (node as? XMLElement)?.attribute(forName: "id")?.stringValue ?? node.xmlString(options: [.nodePreserveAll])
        }
        XCTAssertEqual(tokens[0], "before")
        XCTAssertEqual(tokens[1], "x")
        XCTAssertEqual(tokens[2], "<!--inside-->")
        XCTAssertTrue(tokens[3].contains("payload"))
        XCTAssertEqual(tokens[4], "<!--between-->")
        XCTAssertEqual(tokens[5], "y")
    }
    func testAllExplicitNestedWrappersFlattenRegardlessRequestOrderAndKeepUnselectedIntermediate() throws {
        let original = try source(
            "<component id='a'>A<component id='keep'>K<component id='b'>B<component id='c'/></component>Z</component><component id='d'/></component><component id='tail'/>"
        )
        for ids in [["a", "b"], ["b", "a"], ["b", "a", "a"]] {
            let changed = try original.applying(.ungroupComponents(ids: ids))
            XCTAssertEqual(try changed.components().map(\.id), ["keep", "c", "d", "tail"])
            XCTAssertEqual(try changed.components().first?.childIDs, ["c"])
            let xml = String(decoding: changed.modelXML, as: UTF8.self)
            XCTAssertTrue(xml.contains(">KB"))
            XCTAssertTrue(xml.contains("/>Z"))
            let container = try XCTUnwrap(
                XMLDocument(data: changed.modelXML).rootElement()?.elements(forName: "components").first)
            XCTAssertEqual(container.children?.first?.stringValue, "A")
        }
        var nested = "<component id='leaf'/>"
        for index in (0..<48).reversed() { nested = "<component id='g\(index)'>\(nested)</component>" }
        let deep = try source(nested)
        let flat = try deep.applying(.ungroupComponents(ids: (0..<48).map { "g\($0)" }))
        XCTAssertEqual(try flat.components().map(\.id), ["leaf"])
    }
    func testSafeNamespaceAndIdenticalInheritedContextsIncludingAbsoluteResetsAndOverrides() throws {
        let cases = [
            "<component id='parent' xml:lang='en' xml:space='preserve'><component id='g' xml:lang='en' xml:space='preserve' xmlns:q='urn:q'><component id='child' future='q:Value'/></component></component>",
            "<component id='parent' xml:base='https://example.invalid/root/'><component id='g' xml:base='https://example.invalid/root/'><component id='child'/></component></component>",
            "<component id='parent' xml:base='https://example.invalid/root/'><component id='g' xml:base='relative/' xml:lang='fr'><component id='child' xml:base='https://example.invalid/child/' xml:lang='en'/></component></component>",
            "<component id='parent' xml:base='https://example.invalid/root/'><component id='g'><component id='child' xml:base='relative/'/></component></component>",
        ]
        for text in cases {
            let changed = try source(text).applying(.ungroupComponents(ids: ["g"]))
            XCTAssertEqual(try changed.components().map(\.id), ["parent", "child"])
        }
        let extensionOnly = try source(
            "<component id='g' xmlns:q='urn:q'><q:payload future='q:Value'/><!--keep--></component>")
        let promoted = try extensionOnly.applying(.ungroupComponents(ids: ["g"]))
        XCTAssertTrue(try promoted.components().isEmpty)
        let container = try XCTUnwrap(
            XMLDocument(data: promoted.modelXML).rootElement()?.elements(forName: "components").first)
        let payload = try XCTUnwrap((container.children ?? []).first as? XMLElement)
        XCTAssertEqual(payload.uri, "urn:q")
        XCTAssertEqual(payload.attribute(forName: "future")?.stringValue, "q:Value")
    }
    func testChangingOrUnprovenInheritedContextsRejectAtomicallyIncludingFullRelativeBaseChain() throws {
        for (attribute, outer, inner) in [
            ("xml:lang", "en", "fr"), ("xml:space", "default", "preserve"),
            ("xml:base", "a/", "a/"), ("xml:base", "https://example.invalid/root/", "relative/"),
            ("xml:base", "https://example.invalid/root/", "bad URI"),
        ] {
            let original = try source(
                "<component id='outer' xml:base='https://example.invalid/'><component id='parent' \(attribute)='\(outer)'><component id='g' \(attribute)='\(inner)'><component id='child'/></component></component></component>"
            )
            XCTAssertNotNil(try original.components().first { $0.id == "g" })
            XCTAssertThrowsError(try original.applying(.ungroupComponents(ids: ["g"]))) {
                XCTAssertEqual($0 as? ComponentUngroupError, .inheritedContext(componentID: "g", attribute: attribute))
            }
            XCTAssertNotNil(try original.components().first { $0.id == "g" })
        }
    }
    func testExactArrayValidationLeavesNoopAndOneUndoRetainArchiveEditingStateAndRedo() throws {
        let nfd = "cafe\u{301}"
        let nfc = "caf\u{e9}"
        let original = try source(
            "<component id='\(nfd)'><component id='child'/></component><component id='leaf'/><component id='empty'/>")
        for ids in [[nfd, nfc], [nfc, nfd]] {
            XCTAssertThrowsError(try original.applying(.ungroupComponents(ids: ids))) {
                guard case .missingComponent(let id) = $0 as? DocumentError else {
                    return XCTFail("Missing exact identity")
                }
                XCTAssertEqual(Array(id.utf8), Array(nfc.utf8))
            }
        }
        var history = DocumentHistory(document: original)
        let before = history.previewIdentity
        try history.apply(.ungroupComponents(ids: [nfd]))
        XCTAssertNotEqual(history.previewIdentity.geometry, before.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, before.materials)
        history.undo()
        XCTAssertTrue(history.document.hasSameEditingState(as: original))
        for ids: [String] in [[], ["leaf", "empty"]] {
            try history.apply(.ungroupComponents(ids: ids))
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertTrue(history.canRedo)
        }
        history.redo()
        XCTAssertEqual(try history.document.components().map(\.id), ["child", "leaf", "empty"])
    }
    func testRepeatedInvalidAbsoluteLookingBasesCannotMasqueradeAsIndependentResets() throws {
        for base in [
            "https://example.invalid/path[bad", "https://user[bad]@example.invalid/",
            "http://[broken", "https://example.invalid/a|b", "https://example.invalid/%Q1", "future:bad value",
        ] {
            let original = try source(
                "<component id='parent' xml:base='https://example.invalid/root/'><component id='g' xml:base='\(base)'><component id='child' xml:base='\(base)'/></component></component>"
            )
            XCTAssertNotNil(try original.components().first { $0.id == "g" })
            XCTAssertThrowsError(try original.applying(.ungroupComponents(ids: ["g"]))) {
                XCTAssertEqual($0 as? ComponentUngroupError, .inheritedContext(componentID: "g", attribute: "xml:base"))
            }
        }
    }

    func testDeepDistinctNamespaceFramesPromoteOrderedPayloadsWithoutLosingInheritedQNameBindings() throws {
        var content = "<component id='leaf'/>"
        for index in (0..<48).reversed() {
            content =
                "<component id='g\(index)' xmlns:q\(index)='urn:namespace:\(index)'><q\(index):payload ref='q\(index):Value'/>\(content)</component>"
        }
        let original = try source(content)
        let changed = try original.applying(.ungroupComponents(ids: (0..<48).reversed().map { "g\($0)" }))
        XCTAssertEqual(try changed.components().map(\.id), ["leaf"])
        let container = try XCTUnwrap(
            XMLDocument(data: changed.modelXML).rootElement()?.elements(forName: "components").first)
        let payloads = (container.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name != "component" }
        XCTAssertEqual(payloads.count, 48)
        for (index, payload) in payloads.enumerated() {
            XCTAssertEqual(payload.uri, "urn:namespace:\(index)")
            XCTAssertEqual(payload.attribute(forName: "ref")?.stringValue, "q\(index):Value")
            for inherited in 0...index {
                XCTAssertEqual(
                    payload.namespaces?.first { $0.name == "q\(inherited)" }?.stringValue, "urn:namespace:\(inherited)")
            }
        }
    }

    func testNonWhitespaceTextAndCDATARejectChangingInheritedNamespaceBindings() throws {
        for text in ["q:Value", "<![CDATA[q:Value]]>", "<![CDATA[\u{00A0}]]>"] {
            let original = try source("<component id='g' xmlns:q='urn:removed'>\(text)</component>")
            XCTAssertNotNil(try original.components().first { $0.id == "g" })
            XCTAssertThrowsError(try original.applying(.ungroupComponents(ids: ["g"]))) {
                XCTAssertEqual($0 as? ComponentUngroupError, .textNamespaceContext(componentID: "g"))
            }
        }
    }

    func testTextCDATAWhitespaceCommentsAndPIKeepTheirApprovedUnchangedNamespacePolicies() throws {
        for text in ["q:Value", "<![CDATA[q:Value]]>"] {
            for binding in ["", "xmlns:q='urn:kept'"] {
                let original = try source(
                    "<component id='parent' xmlns:q='urn:kept'><component id='g' \(binding)>\(text)</component></component>"
                )
                let changed = try original.applying(.ungroupComponents(ids: ["g"]))
                XCTAssertEqual(try changed.components().map(\.id), ["parent"])
                XCTAssertTrue(String(decoding: changed.modelXML, as: UTF8.self).contains("q:Value"))
            }
        }
        for payload in ["opaque text", "<![CDATA[opaque text]]>"] {
            let changed = try source("<component id='g'>\(payload)</component>").applying(
                .ungroupComponents(ids: ["g"]))
            XCTAssertTrue(try changed.components().isEmpty)
            XCTAssertTrue(String(decoding: changed.modelXML, as: UTF8.self).contains("opaque text"))
        }
        let formattingOnly = try source("<component id='g' xmlns:q='urn:removed'> \n</component>")
        XCTAssertFalse(try formattingOnly.components().first?.hasChildXML == true)
        XCTAssertEqual(try formattingOnly.applying(.ungroupComponents(ids: ["g"])).encoded(), formattingOnly.encoded())
        for payload in ["<![CDATA[ \n]]>", "<!--q:Value-->", "<?future q:Value?>"] {
            let changed = try source("<component id='g' xmlns:q='urn:removed'>\(payload)</component>").applying(
                .ungroupComponents(ids: ["g"]))
            XCTAssertTrue(try changed.components().isEmpty)
        }
    }

    func testNamespaceShadowingRetainsNearestBindingAndChildOverrides() throws {
        let original = try source(
            "<component id='keep' xmlns:q='urn:destination'><component id='outer' xmlns:q='urn:outer' xmlns:r='urn:outer-only'><component id='inner' xmlns:q='urn:inner'><component id='a'><q:payload/><r:payload/></component><component id='b' xmlns:q='urn:local'><q:payload/></component></component></component></component>"
        )
        let edited = try original.applying(.ungroupComponents(ids: ["inner", "outer"]))
        XCTAssertEqual(try edited.components().map(\.id), ["keep", "a", "b"])
        let model = try XMLDocument(data: edited.modelXML)
        let parent = try XCTUnwrap(
            model.rootElement()?.elements(forName: "components").first?.elements(forName: "component").first)
        let promoted = parent.elements(forName: "component")
        let a = try XCTUnwrap(promoted.first)
        let b = try XCTUnwrap(promoted.last)
        XCTAssertEqual(a.elements(forLocalName: "payload", uri: "urn:inner").count, 1)
        XCTAssertEqual(a.elements(forLocalName: "payload", uri: "urn:outer-only").count, 1)
        XCTAssertEqual(b.elements(forLocalName: "payload", uri: "urn:local").count, 1)
    }

    func testRawSelectionQuotaPrecedesDeduplicationAndPreservesSource() throws {
        let original = try source("<component id='g'><component id='leaf'/></component>")
        let ids = Array(repeating: "g", count: ComponentUngroupPlan.maximumCount + 1)
        XCTAssertThrowsError(try ComponentUngroupPlan(components: original.components(), ids: ids)) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        let before = original.encoded()
        XCTAssertThrowsError(try original.applying(.ungroupComponents(ids: ids))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        XCTAssertEqual(original.encoded(), before)
    }

}
