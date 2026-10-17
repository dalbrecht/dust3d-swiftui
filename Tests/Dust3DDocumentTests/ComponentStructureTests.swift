import Dust3DDocument
import Foundation
import XCTest

final class ComponentStructureTests: XCTestCase {
    private func document(
        _ components: String =
            "<component id='a' future='A'><component id='leaf' linkDataType='partId' linkData='p' future='leaf'/><future data='retained'/></component><!--between--><component id='b' future='B'/><component id='c' linkDataType='future' linkData='opaque'/>",
        nodes: String = "<node id='n' partId='p' x='1' y='2' z='3' radius='.1'/>", edges: String = ""
    ) throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='root'><nodes>\(nodes)</nodes><edges>\(edges)</edges><parts><part id='p' locked='true' visible='false' disabled='true'/></parts><components>\(components)</components></canvas>"
                .utf8)
        let header =
            "<ds3 future='archive'><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4' future='asset'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    func testGroupingUsesSourceSiblingOrderRetainsSubtreesAndLeavesUnrelatedDataIntact() throws {
        let original = try document()
        let changed = try original.applying(.groupComponents(ids: ["c", "a"], groupID: "g"))
        let components = try changed.components()
        XCTAssertEqual(components.filter { $0.parentID == nil }.map(\.id), ["g", "b"])
        XCTAssertEqual(components.first { $0.id == "g" }?.childIDs, ["a", "c"])
        XCTAssertEqual(components.first { $0.id == "leaf" }?.parentID, "a")
        XCTAssertEqual(components.first { $0.id == "c" }?.linkData, "opaque")
        XCTAssertTrue(components.first { $0.id == "g" }?.isGroup == true)
        XCTAssertFalse(components.first { $0.id == "leaf" }?.isGroup == true)
        XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        XCTAssertEqual(
            try changed.editorContents().nodes.map(\.value), try original.editorContents().nodes.map(\.value))
        let xml = try XMLDocument(data: changed.modelXML)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//component[@id='a']").first as? XMLElement)?.attribute(forName: "future")?
                .stringValue, "A")
        XCTAssertNotNil(try xml.nodes(forXPath: "//component[@id='a']/future").first)
        XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).components(), components)
        let nested = try original.applying(.groupComponents(ids: ["leaf"], groupID: "nested"))
        XCTAssertEqual(try nested.components().first { $0.id == "a" }?.childIDs, ["nested"])
        XCTAssertEqual(try nested.components().first { $0.id == "nested" }?.childIDs, ["leaf"])
    }
    func testUngroupPromotesChildrenAtGroupPositionAndHistoryRestoresRemovedSettings() throws {
        let original = try document()
        let changed = try original.applying(.ungroupComponent(id: "a"))
        XCTAssertEqual(try changed.components().filter { $0.parentID == nil }.map(\.id), ["leaf", "b", "c"])
        XCTAssertNil(try changed.components().first { $0.id == "a" })
        let xml = try XMLDocument(data: changed.modelXML)
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//components/future").first as? XMLElement)?.attribute(forName: "data")?
                .stringValue, "retained")
        XCTAssertEqual(
            (try xml.nodes(forXPath: "//component[@id='leaf']").first as? XMLElement)?.attribute(forName: "future")?
                .stringValue, "leaf")
        XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        var history = DocumentHistory(document: original)
        try history.apply(.ungroupComponent(id: "a"))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
        XCTAssertEqual(try original.applying(.ungroupComponent(id: "b")).encoded(), original.encoded())
    }
    func testReparentAppendsToValidGroupOrRootAndRejectsCyclesAndLinkedDestinations() throws {
        let original = try document()
        let changed = try original.applying(.reparentComponent(id: "b", parentID: "a"))
        XCTAssertEqual(try changed.components().first { $0.id == "a" }?.childIDs, ["leaf", "b"])
        XCTAssertEqual(try changed.components().filter { $0.parentID == nil }.map(\.id), ["a", "c"])
        XCTAssertEqual(try changed.applying(.reparentComponent(id: "b", parentID: "a")).encoded(), changed.encoded())
        let rooted = try changed.applying(.reparentComponent(id: "b", parentID: nil))
        XCTAssertEqual(try rooted.components().filter { $0.parentID == nil }.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(try original.applying(.reparentComponent(id: "b", parentID: nil)).encoded(), original.encoded())
        for (id, parent) in [("a", "a"), ("a", "leaf"), ("a", "b"), ("b", "leaf"), ("b", "c")] {
            XCTAssertThrowsError(try changed.applying(.reparentComponent(id: id, parentID: parent))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
            }
        }
        XCTAssertThrowsError(try original.applying(.reparentComponent(id: "b", parentID: "missing"))) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
        }
        XCTAssertThrowsError(try original.applying(.reparentComponent(id: "missing", parentID: nil)))
        XCTAssertEqual(original.encoded(), try document().encoded())
    }
    func testInvalidGroupingAndUngroupTargetsRejectAtomically() throws {
        let original = try document()
        for ids in [[], ["a", "a"], ["a", "leaf"], ["a", "missing"]] {
            XCTAssertThrowsError(try original.applying(.groupComponents(ids: ids, groupID: "g")))
        }
        for id in ["", "a", " ", "bad\0id", "bad\u{FFFF}id", String(repeating: "x", count: 129)] {
            XCTAssertThrowsError(try original.applying(.groupComponents(ids: ["b"], groupID: id)))
        }
        XCTAssertNoThrow(
            try original.applying(.groupComponents(ids: ["b"], groupID: String(repeating: "x", count: 128))))
        for id in ["leaf", "c", "missing"] { XCTAssertThrowsError(try original.applying(.ungroupComponent(id: id))) }
        for xml in ["<component id='same'/><component id='same'/>", "<future id='unknown'/>"] {
            let malformed = try document(xml)
            XCTAssertThrowsError(try malformed.applying(.groupComponents(ids: ["same"], groupID: "g")))
            XCTAssertThrowsError(try malformed.applying(.ungroupComponent(id: "same")))
            XCTAssertThrowsError(try malformed.applying(.reparentComponent(id: "same", parentID: nil)))
        }
        XCTAssertEqual(original.encoded(), try document().encoded())
    }
    func testOnlyEmptyLinkAttributesAreSupportedGroupsAndOpaqueLinksStayIntact() throws {
        let original = try document(
            "<component id='empty' linkDataType='' linkData=''/><component id='data' linkData='opaque'/><component id='type' linkDataType='future'/>"
        )
        XCTAssertEqual(try original.components().map(\.isGroup), [true, false, false])
        for parent in ["data", "type"] {
            XCTAssertThrowsError(try original.applying(.reparentComponent(id: "empty", parentID: parent))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
            }
        }
        let grouped = try original.applying(.groupComponents(ids: ["data", "type"], groupID: "g"))
        let ungrouped = try grouped.applying(.ungroupComponent(id: "g"))
        XCTAssertEqual(try ungrouped.components().map(\.id), ["empty", "data", "type"])
        XCTAssertEqual(try ungrouped.components().map(\.linkData), ["", "opaque", nil])
        XCTAssertEqual(try ungrouped.components().map(\.linkDataType), ["", nil, "future"])
    }

    func testGroupingAndUngroupingDoNotWriteIntoPartLinkedOrOpaqueParents() throws {
        for (kind, data) in [("partId", "p"), ("future", "opaque")] {
            let original = try document(
                "<component id='parent' linkDataType='\(kind)' linkData='\(data)'><component id='child'/><component id='group'><component id='inner'/></component></component>"
            )
            XCTAssertThrowsError(try original.applying(.groupComponents(ids: ["child"], groupID: "g"))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
            }
            XCTAssertThrowsError(try original.applying(.ungroupComponent(id: "group"))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
            }
            let repaired = try original.applying(.reparentComponent(id: "child", parentID: nil))
            XCTAssertNil(try repaired.components().first { $0.id == "child" }?.parentID)
            XCTAssertEqual(try repaired.components().first { $0.id == "parent" }?.linkData, data)
            XCTAssertEqual(try repaired.components().first { $0.id == "parent" }?.childIDs, ["group"])
        }
    }

    func testFreshGroupIdentityRejectsEverySemanticCategoryAndUUIDAlias() throws {
        let original = try document(edges: "<edge id='e' from='n' to='n'/>")
        for id in ["n", "e", "p", "a"] {
            XCTAssertThrowsError(try original.applying(.groupComponents(ids: ["b"], groupID: id))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
            }
        }
        let identifiers = [
            "{11111111-1111-4111-8111-111111111111}", "{22222222-2222-4222-8222-222222222222}",
            "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}",
        ]
        for useBraces in [true, false] {
            let source = identifiers.map { useBraces ? $0 : String($0.dropFirst().dropLast()) }
            let value = try Dust3DDocument(
                snapshotXML: Data(
                    "<canvas><nodes><node id='\(source[0])' partId='\(source[2])' x='0' y='0' z='0' radius='.1'/></nodes><edges><edge id='\(source[1])' from='\(source[0])' to='\(source[0])'/></edges><parts><part id='\(source[2])'/></parts><components><component id='\(source[3])' linkDataType='partId' linkData='\(source[2])'/></components></canvas>"
                        .utf8))
            for id in identifiers.flatMap({ [$0, String($0.dropFirst().dropLast())] }) {
                XCTAssertThrowsError(try value.applying(.groupComponents(ids: [source[3]], groupID: id))) {
                    XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
                }
            }
            XCTAssertNoThrow(try value.applying(.groupComponents(ids: [source[3]], groupID: "fresh")))
        }
        let opaque = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><components><component id='a'/></components><future id='g'/></canvas>".utf8))
        XCTAssertNoThrow(try opaque.applying(.groupComponents(ids: ["a"], groupID: "g")))
    }

    func testUngroupRetainsInheritedExtensionAndQNameNamespaceBindings() throws {
        let original = try document(
            "<component id='group' xmlns:ext='urn:extension' xmlns:q='urn:qualified'><component id='child' ext:flag='child' futureType='q:Thing'><ext:future/></component><ext:opaque ext:flag='direct'/></component>"
        )
        let changed = try original.applying(.ungroupComponent(id: "group"))
        let container = try XCTUnwrap(
            XMLDocument(data: changed.modelXML).rootElement()?.elements(forName: "components").first)
        let child = try XCTUnwrap(container.elements(forName: "component").first)
        XCTAssertEqual(child.attribute(forName: "ext:flag")?.uri, "urn:extension")
        XCTAssertEqual(child.elements(forName: "ext:future").first?.uri, "urn:extension")
        XCTAssertEqual(child.attribute(forName: "futureType")?.stringValue, "q:Thing")
        XCTAssertEqual(child.namespaces?.first { $0.name == "q" }?.stringValue, "urn:qualified")
        XCTAssertEqual(container.elements(forName: "ext:opaque").first?.uri, "urn:extension")
        var history = DocumentHistory(document: original)
        try history.apply(.ungroupComponent(id: "group"))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
    }

    func testReparentRetainsOldDefaultExtensionAndQNameNamespacesAcrossConflictingDestination() throws {
        let original = try document(
            "<component id='source' xmlns='urn:source' xmlns:ext='urn:extension' xmlns:q='urn:qualified'><component id='moving' ext:flag='source' futureType='q:Thing'><ext:future/></component></component><component id='destination' xmlns='urn:destination' xmlns:ext='urn:other' xmlns:q='urn:other-qualified'><component id='resident'/></component>"
        )
        let wrapped = try original.applying(.groupComponents(ids: ["moving"], groupID: "wrapped"))
        let wrappedContainer = try XCTUnwrap(
            XMLDocument(data: wrapped.modelXML).rootElement()?.elements(forName: "components").first)
        let source = try XCTUnwrap(
            wrappedContainer.elements(forName: "component").first {
                $0.attribute(forName: "id")?.stringValue == "source"
            })
        let wrapper = try XCTUnwrap(source.elements(forName: "component").first)
        XCTAssertEqual(wrapper.uri, "urn:source")
        XCTAssertEqual(wrapper.elements(forName: "component").first?.uri, "urn:source")
        let changed = try original.applying(.reparentComponent(id: "moving", parentID: "destination"))
        let xml = try XMLDocument(data: changed.modelXML)
        let container = try XCTUnwrap(xml.rootElement()?.elements(forName: "components").first)
        let destination = try XCTUnwrap(
            container.elements(forName: "component").first { $0.attribute(forName: "id")?.stringValue == "destination" }
        )
        let moving = try XCTUnwrap(
            (destination.children ?? []).compactMap { $0 as? XMLElement }.first {
                $0.attribute(forName: "id")?.stringValue == "moving"
            })
        XCTAssertEqual(try changed.components().first { $0.id == "moving" }?.parentID, "destination")
        XCTAssertEqual(try changed.components().first { $0.id == "destination" }?.childIDs, ["resident", "moving"])
        XCTAssertEqual(destination.uri, "urn:destination")
        XCTAssertEqual(moving.uri, "urn:source")
        XCTAssertEqual(moving.attribute(forName: "ext:flag")?.uri, "urn:extension")
        XCTAssertEqual(moving.elements(forName: "ext:future").first?.uri, "urn:extension")
        XCTAssertEqual(moving.attribute(forName: "futureType")?.stringValue, "q:Thing")
        XCTAssertEqual(moving.namespaces?.first { $0.name == "q" }?.stringValue, "urn:qualified")
        let reordered = try changed.applying(.reorderComponent(id: "moving", direction: .up))
        XCTAssertEqual(try reordered.components().first { $0.id == "destination" }?.childIDs, ["moving", "resident"])
    }

    func testUnnamespacedSubtreeRemainsUnnamespacedInANamespacedDestination() throws {
        let original = try document("<component id='plain'/><component id='destination' xmlns='urn:destination'/>")
        let changed = try original.applying(.reparentComponent(id: "plain", parentID: "destination"))
        let container = try XCTUnwrap(
            XMLDocument(data: changed.modelXML).rootElement()?.elements(forName: "components").first)
        let destination = try XCTUnwrap(
            container.elements(forName: "component").first { $0.attribute(forName: "id")?.stringValue == "destination" }
        )
        let plain = try XCTUnwrap(
            (destination.children ?? []).compactMap { $0 as? XMLElement }.first { $0.name == "component" })
        XCTAssertTrue((plain.uri ?? "").isEmpty)
        XCTAssertEqual(try changed.components().first { $0.id == "plain" }?.parentID, "destination")
        XCTAssertEqual(
            try changed.applying(.reparentComponent(id: "plain", parentID: "destination")).encoded(), changed.encoded())
    }

    func testInheritedNamespaceExpansionRejectsBeforeStructuralPublication() throws {
        let manyBindings = (0..<501).map { "xmlns:q\($0)='urn:namespace:\($0)'" }.joined(separator: " ")
        let longBinding = "xmlns:q='urn:" + String(repeating: "x", count: 1024 * 1024) + "'"
        for (bindings, childCount) in [(manyBindings, 200), (longBinding, 20)] {
            let children = (0..<childCount).map { "<component id='c\($0)'/>" }.joined()
            let original = try document("<component id='group' \(bindings)>\(children)</component>")
            let bytes = original.encoded()
            XCTAssertThrowsError(try original.applying(.ungroupComponent(id: "group"))) {
                XCTAssertEqual($0 as? DocumentError, .limitExceeded)
            }
            XCTAssertEqual(original.encoded(), bytes)
        }
    }

    func testNetZeroStructuralTransactionsAndNoOpsRetainExactBytesAndRedo() throws {
        let original = try document()
        var history = DocumentHistory(document: original)
        try history.apply(.reorderComponent(id: "b", direction: .up))
        let edited = history.document.encoded()
        XCTAssertTrue(history.undo())
        try history.beginTransaction()
        try history.apply(.groupComponents(ids: ["b", "c"], groupID: "g"))
        try history.apply(.ungroupComponent(id: "g"))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
        try history.beginTransaction()
        try history.apply(.reparentComponent(id: "c", parentID: "a"))
        try history.apply(.reparentComponent(id: "c", parentID: nil))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        try history.apply(.reparentComponent(id: "b", parentID: nil))
        try history.apply(.ungroupComponent(id: "b"))
        XCTAssertTrue(history.canRedo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited)
    }

    func testDepthAndCountLimitsRejectWithoutPublishingAndUnsupportedGraphStaysOpaque() throws {
        XCTAssertThrowsError(
            try document().applying(.groupComponents(ids: Array(repeating: "b", count: 10_001), groupID: "g"))
        ) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        let excessive = try document((0..<10_000).map { "<component id='c\($0)'/>" }.joined())
        XCTAssertThrowsError(try excessive.applying(.groupComponents(ids: ["c0"], groupID: "g"))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        let deep =
            (0..<126).map { "<component id='d\($0)'>" }.joined() + String(repeating: "</component>", count: 126)
            + "<component id='moving'/>"
        let original = try document(deep)
        XCTAssertThrowsError(try original.applying(.reparentComponent(id: "moving", parentID: "d125")))
        XCTAssertThrowsError(try original.applying(.groupComponents(ids: ["d0"], groupID: "g")))
        XCTAssertEqual(original.encoded(), try document(deep).encoded())
        let opaque = try document(nodes: "<node id='unsupported' future='preserved'/>")
        let grouped = try opaque.applying(.groupComponents(ids: ["b"], groupID: "g"))
        let moved = try grouped.applying(.reparentComponent(id: "c", parentID: "g"))
        let ungrouped = try moved.applying(.ungroupComponent(id: "g"))
        XCTAssertThrowsError(try ungrouped.editorContents())
        XCTAssertTrue(String(decoding: ungrouped.modelXML, as: UTF8.self).contains("preserved"))
        XCTAssertEqual(ungrouped.asset(named: "opaque.bin"), opaque.asset(named: "opaque.bin"))
    }
}
