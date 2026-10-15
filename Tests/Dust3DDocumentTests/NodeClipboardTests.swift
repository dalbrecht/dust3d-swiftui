import Dust3DDocument
import Foundation
import XCTest

final class NodeClipboardTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ["a", "b", "c"].enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                    componentID: index == 0 ? "component" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        return try document.applying(.addEdge(id: "ab", from: "a", to: "b"))
            .applying(.addEdge(id: "bc", from: "b", to: "c"))
    }
    func testCopyContainsOnlySelectionAndInternalEdgesAndPasteRemapsAllIdentities() throws {
        let original = try source()
        let clipboard = try original.copyingNodes(["a", "b"])
        XCTAssertEqual(clipboard.selectedNodeIDs, ["a", "b"])
        XCTAssertEqual(try clipboard.document.editorContents().nodes.map(\.id), ["a", "b"])
        XCTAssertEqual(try clipboard.document.editorContents().edges.map(\.id), ["ab"])
        let identities = self.identities(clipboard)
        let pasted = try original.applying(
            .pasteNodes(
                clipboard: clipboard, identities: identities,
                offset: .init(x: 0, y: 0.04, z: 0.04)))
        XCTAssertEqual(try pasted.editorContents().nodes.map(\.id), ["a", "b", "c", "new-a", "new-b"])
        XCTAssertEqual(try pasted.node(id: "new-a").position, .init(x: 0, y: 0.04, z: 0.04))
        XCTAssertEqual(try pasted.editorContents().edges.last?.fromID, "new-a")
        XCTAssertEqual(try pasted.editorContents().edges.last?.toID, "new-b")
        var history = DocumentHistory(document: original)
        try history.apply(
            .pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0.04, z: 0.04)))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), pasted.encoded())
    }
    private func archive(
        _ xml: String, asset: [UInt8]? = nil, assetType: String = "image", metadata: String = "",
        headerNamespaces: String = ""
    )
        throws -> Dust3DDocument
    {
        let model = Data(xml.utf8)
        let entry =
            asset.map { "<\(assetType) name='opaque' offset='\(model.count)' size='\($0.count)' \(metadata)/>" } ?? ""
        let header = "<ds3 \(headerNamespaces)><model name='model.xml' offset='0' size='\(model.count)'/>\(entry)</ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data(asset ?? []))
    }
    private func richSource() throws -> Dust3DDocument {
        try archive(
            """
            <canvas originX='17' xmlns='urn:test'><nodes>
            <node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1' future='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/><node id='b' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='1' y='0' z='0' radius='.2' cutFace='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}'/>
            <node id='c' partId='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' x='2' y='0' z='0' radius='.3' cutFace='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}'><future from='a'/></node>
            <node id='d' partId='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' x='3' y='0' z='0' radius='.4'/><node id='e' partId='other' x='4' y='0' z='0' radius='.5'/>
            </nodes><edges><edge id='ab' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' from='a' to='b' future='a'/></edges>
            <parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' cutFace='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' from='a' future='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/><part id='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' deformWidth='.8'/><part id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}'/><part id='other'/></parts>
            <components><component id='group' future='group'><component id='pc' linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' linkDataType='partId' color='#123456'><future linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/><component id='unselected' linkData='other' linkDataType='partId'/></component><component id='qc' linkData='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' linkDataType='partId'/></component>
            <component id='rc' linkData='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId'/><component id='repeat' linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' linkDataType='partId'/>
            <component id='outside' linkData='other' linkDataType='partId'><component id='nested' linkData='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' linkDataType='partId'/></component>
            <component id='drop' linkData='other' linkDataType='partId'/></components><animations><animation id='not-copied'/></animations><future id='not-copied'/></canvas>
            """, asset: [0, 255], metadata: "future='asset'")
    }
    private func identities(_ clipboard: NodeClipboard) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: clipboard.identifiers.map { id in
                let fresh = id.hasPrefix("{") ? "{99999999-9999-4999-8999-\(id.dropLast().suffix(12))}" : "new-\(id)"
                return (id, fresh)
            })
    }
    func testProfilesHierarchyNamespacesAndOpaqueMetadataAreRetained() throws {
        let source = try richSource()
        let clipboard = try source.copyingNodes(["a"])
        XCTAssertEqual(clipboard.selectedNodeIDs, ["a"])
        XCTAssertEqual(try clipboard.document.editorContents().nodes.map(\.id), ["a", "c", "d"])
        XCTAssertTrue(try clipboard.document.editorContents().edges.isEmpty)
        let xml = try XMLDocument(data: clipboard.document.modelXML)
        let root = try XCTUnwrap(xml.rootElement())
        XCTAssertEqual(root.uri, "urn:test")
        XCTAssertTrue(root.elements(forName: "animations").isEmpty)
        XCTAssertTrue(root.elements(forName: "future").isEmpty)
        let groups = root.elements(forName: "components").first?.elements(forName: "component") ?? []
        XCTAssertEqual(
            groups.map { $0.attribute(forName: "id")?.stringValue ?? "" }, ["group", "rc", "repeat", "outside"])
        XCTAssertNil(groups.last?.attribute(forName: "linkData"))
        XCTAssertEqual(groups.first?.elements(forName: "component").first?.elements(forName: "component").count, 0)
        let destination = try archive("<canvas originX='99'><future keep='destination'/></canvas>")
        let pasted = try destination.applying(
            .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        XCTAssertEqual(pasted.asset(named: "opaque"), Data([0, 255]))
        let result = try XMLDocument(data: pasted.modelXML)
        XCTAssertEqual(result.rootElement()?.attribute(forName: "originX")?.stringValue, "99")
        XCTAssertEqual(
            result.rootElement()?.elements(forName: "future").first?.attribute(forName: "keep")?.stringValue,
            "destination")
        let part = result.rootElement()?.elements(forName: "parts").first?.elements(forName: "part").first
        XCTAssertEqual(part?.attribute(forName: "cutFace")?.stringValue, "{99999999-9999-4999-8999-bbbbbbbbbbbb}")
        XCTAssertEqual(part?.attribute(forName: "from")?.stringValue, "a")
        XCTAssertEqual(part?.attribute(forName: "future")?.stringValue, "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}")
        let node = result.rootElement()?.elements(forName: "nodes").first?.elements(forName: "node").first
        XCTAssertEqual(node?.attribute(forName: "future")?.stringValue, "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}")
        let newGroup = result.rootElement()?.elements(forName: "components").first?.elements(forName: "component").first
        let component = newGroup?.elements(forName: "component").first
        XCTAssertEqual(component?.attribute(forName: "linkData")?.stringValue, "{99999999-9999-4999-8999-aaaaaaaaaaaa}")
        let opaque = component?.children?.compactMap { $0 as? XMLElement }.first { $0.localName == "future" }
        XCTAssertEqual(opaque?.attribute(forName: "linkData")?.stringValue, "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}")
        XCTAssertEqual(opaque?.uri, "urn:test")
        XCTAssertEqual(try pasted.editorContents().nodes.map(\.id), ["new-a", "new-c", "new-d"])
        XCTAssertEqual(try source.editorContents().nodes.count, 5)
    }
    func testAssetSharingAndConflictsAreAtomic() throws {
        let source = try richSource()
        let clipboard = try source.copyingNodes(["a"])
        let command = DocumentCommand.pasteNodes(
            clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0))
        let destinationXML = "<canvas><future keep='yes'/></canvas>"
        let identical = try archive(destinationXML, asset: [0, 255], metadata: "future='asset'")
        let pasted = try identical.applying(command)
        XCTAssertEqual(pasted.asset(named: "opaque"), Data([0, 255]))
        for conflict in [
            try archive(destinationXML, asset: [1, 2], metadata: "future='asset'"),
            try archive(destinationXML, asset: [0, 255], assetType: "mesh", metadata: "future='asset'"),
            try archive(destinationXML, asset: [0, 255], metadata: "future='other'"),
        ] {
            var history = DocumentHistory(document: conflict)
            XCTAssertThrowsError(try history.apply(command)) {
                XCTAssertEqual($0 as? DocumentError, .conflictingAsset("opaque"))
            }
            XCTAssertEqual(history.document.encoded(), conflict.encoded())
            XCTAssertFalse(history.canUndo)
        }
    }
    func testInvalidSelectionsIdentitiesAndOffsetsRejectWithoutPublication() throws {
        let source = try self.source()
        XCTAssertThrowsError(try source.copyingNodes([]))
        XCTAssertThrowsError(try source.copyingNodes(["missing"]))
        let unassigned = try archive("<canvas><nodes><node id='x' x='0' y='0' z='0' radius='.1'/></nodes></canvas>")
        XCTAssertThrowsError(try unassigned.copyingNodes(["x"]))
        let clipboard = try source.copyingNodes(["a", "b"])
        var plans: [[String: String]] = [[:], identities(clipboard)]
        plans[1]["extra"] = "new-extra"
        for replacement in ["", "a", String(repeating: "x", count: 129), "new-b"] {
            var map = identities(clipboard)
            map["a"] = replacement
            plans.append(map)
        }
        for map in plans {
            XCTAssertThrowsError(
                try source.applying(.pasteNodes(clipboard: clipboard, identities: map, offset: .init(x: 0, y: 0, z: 0)))
            )
        }
        for offset in [
            NodePosition(x: .nan, y: 0, z: 0), .init(x: .infinity, y: 0, z: 0), .init(x: 1_000_001, y: 0, z: 0),
            .init(x: 1_000_000, y: 0, z: 0),
        ] {
            XCTAssertThrowsError(
                try source.applying(
                    .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: offset)))
        }
        XCTAssertThrowsError(try NodeClipboard(document: source, selectedNodeIDs: []))
        XCTAssertThrowsError(try NodeClipboard(document: source, selectedNodeIDs: ["missing"]))
        XCTAssertThrowsError(try NodeClipboard(document: unassigned, selectedNodeIDs: ["x"]))
    }
    func testDisconnectedSelectionRetainsPartAndKnownEdgeFieldsRemapOnly() throws {
        let source = try self.source()
        let clipboard = try source.copyingNodes(["a", "c"])
        XCTAssertEqual(try clipboard.document.editorContents().nodes.count, 2)
        XCTAssertTrue(try clipboard.document.editorContents().edges.isEmpty)
        let pasted = try source.applying(
            .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        XCTAssertEqual(
            try pasted.partSplitRequirements(for: ["{99999999-9999-4999-8999-aaaaaaaaaaaa}"]).first?
                .additionalPartCount, 1)
        let rich = try richSource().copyingNodes(["a", "b"])
        let all = try source.applying(
            .pasteNodes(clipboard: rich, identities: identities(rich), offset: .init(x: 0, y: 0, z: 0)))
        let xml = try XMLDocument(data: all.modelXML)
        let edge = xml.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge").last
        XCTAssertEqual(edge?.attribute(forName: "partId")?.stringValue, "{99999999-9999-4999-8999-aaaaaaaaaaaa}")
        XCTAssertEqual(edge?.attribute(forName: "future")?.stringValue, "a")
    }

    func testImportedFragmentRejectsInvalidIdentityTopologyAndProfileData() throws {
        let valid =
            "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1'/><node id='b' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='1' y='0' z='0' radius='.1'/></nodes><edges><edge id='ab' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' from='a' to='b'/></edges><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts><components><component id='component' linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' linkDataType='partId'/></components></canvas>"
        let invalid = [
            valid.replacingOccurrences(of: "id='component'", with: "id='a'"),
            valid.replacingOccurrences(of: "id='component'", with: ""),
            valid.replacingOccurrences(of: "id='component'", with: "id='\(String(repeating: "x", count: 129))'"),
            valid.replacingOccurrences(
                of: "linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'", with: "linkData='missing'"),
            valid.replacingOccurrences(
                of: "<part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/>",
                with:
                    "<part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' cutFace='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/>"
            ),
            valid.replacingOccurrences(of: "to='b'", with: "to='a'"),
            valid.replacingOccurrences(
                of: "<edge id='ab' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'",
                with: "<edge id='ab' partId='wrong'"),
            valid.replacingOccurrences(of: "</components>", with: "</components><components/>"),
            valid.replacingOccurrences(
                of: "</edges>", with: "<edge id='ab2' from='a' to='b'/><edge id='ab3' from='a' to='b'/></edges>"),
            valid.replacingOccurrences(
                of: "id='b' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'",
                with: "id='b' partId='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}'"
            ).replacingOccurrences(
                of: "</parts>", with: "<part id='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}'/></parts>"),
        ]
        for xml in invalid { XCTAssertThrowsError(try NodeClipboard(document: archive(xml), selectedNodeIDs: ["a"])) }
    }
    func testProfileClosureRevisitsNodesOfPartThatWasInitiallyPartial() throws {
        let xml =
            "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1'/><node id='b' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='1' y='0' z='0' radius='.1' cutFace='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}'/><node id='c' partId='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' x='2' y='0' z='0' radius='.1'/><node id='d' partId='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' x='3' y='0' z='0' radius='.1'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/><part id='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' cutFace='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/><part id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}'/></parts></canvas>"
        let clipboard = try archive(xml).copyingNodes(["a", "c"])
        XCTAssertEqual(try clipboard.document.editorContents().nodes.map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(clipboard.selectedNodeIDs, ["a", "c"])
    }
    func testPastingIntoMissingContainersAndArchiveWithEmptyAsset() throws {
        let source = try archive(
            "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts></canvas>",
            asset: [])
        let clipboard = try source.copyingNodes(["a"])
        let destination = try archive("<canvas/>")
        let pasted = try destination.applying(
            .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        XCTAssertEqual(pasted.asset(named: "opaque"), Data())
        XCTAssertEqual(try pasted.editorContents().nodes.map(\.id), ["new-a"])
    }
    func testPastedNodeAndPartCountsAreBounded() throws {
        let nodes = (0..<10_000).map {
            "<node id='n\($0)' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1'/>"
        }.joined()
        let large = try archive(
            "<canvas><nodes>\(nodes)</nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts></canvas>"
        )
        let clipboard = try NodeClipboard(document: large, selectedNodeIDs: ["n0"])
        XCTAssertThrowsError(
            try source().applying(
                .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        ) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
        for container in ["parts", "components"] {
            let entries = (0..<10_000).map { index in
                container == "parts"
                    ? "<part id='p\(index)'/>"
                    : "<component id='c\(index)' linkData='p0' linkDataType='partId'/>"
            }.joined()
            let parts = container == "parts" ? entries : "<part id='p0'/>"
            let components = container == "components" ? entries : ""
            let value = try archive(
                "<canvas><nodes><node id='a' partId='p0' x='0' y='0' z='0' radius='.1'/></nodes><parts>\(parts)</parts><components>\(components)</components></canvas>"
            )
            let fragment = try NodeClipboard(document: value, selectedNodeIDs: ["a"])
            XCTAssertThrowsError(
                try source().applying(
                    .pasteNodes(clipboard: fragment, identities: identities(fragment), offset: .init(x: 0, y: 0, z: 0)))
            ) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
        }
    }

    func testNamedCutFaceIsNotRemappedAsAnUnrelatedNodeIdentity() throws {
        let source = try archive(
            "<canvas><nodes><node id='Quad' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1' cutFace='Quad'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' cutFace='Quad'/></parts></canvas>"
        )
        let clipboard = try source.copyingNodes(["Quad"])
        let pasted = try source.applying(
            .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        let root = try XMLDocument(data: pasted.modelXML).rootElement()
        XCTAssertEqual(
            root?.elements(forName: "parts").first?.elements(forName: "part").last?.attribute(forName: "cutFace")?
                .stringValue, "Quad")
        XCTAssertEqual(
            root?.elements(forName: "nodes").first?.elements(forName: "node").last?.attribute(forName: "cutFace")?
                .stringValue, "Quad")
    }

    func testInheritedNamespacesSurviveMovingObjectsIntoAnotherDocument() throws {
        let source = try archive(
            "<canvas xmlns='urn:source' xmlns:ext='urn:extension'><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1' ext:flag='value'><ext:future/></node></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts><components><component id='component' linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' linkDataType='partId'/></components></canvas>"
        )
        let clipboard = try source.copyingNodes(["a"])
        let destination = try archive("<canvas xmlns='urn:destination'><nodes/><parts/><components/></canvas>")
        let pasted = try destination.applying(
            .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        let root = try XMLDocument(data: pasted.modelXML).rootElement()
        XCTAssertEqual(try pasted.editorContents().nodes.map(\.id), ["new-a"])
        XCTAssertEqual(root?.uri, "urn:destination")
        let node = root?.elements(forName: "nodes").first?.elements(forName: "node").first
        XCTAssertEqual(node?.uri, "urn:destination")
        XCTAssertEqual(node?.attribute(forName: "ext:flag")?.uri, "urn:extension")
        XCTAssertEqual((node?.children?.first as? XMLElement)?.uri, "urn:extension")
    }

    func testInheritedAssetNamespaceBindingsArePreservedAndCompared() throws {
        let xml =
            "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts></canvas>"
        let source = try archive(
            xml, asset: [1, 2], metadata: "ext:flag='value'", headerNamespaces: "xmlns:ext='urn:source'")
        let clipboard = try source.copyingNodes(["a"])
        let command = DocumentCommand.pasteNodes(
            clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0))
        let pasted = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(command)
        let bytes = pasted.encoded()
        let lineEnd = try XCTUnwrap(bytes.firstIndex(of: 10))
        let offset = try XCTUnwrap(
            Int(
                String(decoding: bytes[..<lineEnd], as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).last ?? ""
            ))
        let header = try XMLDocument(data: Data(bytes[(lineEnd + 1)..<offset]))
        XCTAssertEqual(
            header.rootElement()?.elements(forName: "image").first?.attribute(forName: "ext:flag")?.uri, "urn:source")
        let conflict = try archive(
            "<canvas/>", asset: [1, 2], metadata: "ext:flag='value'", headerNamespaces: "xmlns:ext='urn:other'")
        XCTAssertThrowsError(try conflict.applying(command)) {
            XCTAssertEqual($0 as? DocumentError, .conflictingAsset("opaque"))
        }
    }

    func testUnnamespacedGraphAdoptsCanvasNamespaceWithoutChangingOpaqueChildNamespace() throws {
        let source = try archive(
            "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1'><future/></node></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts></canvas>"
        )
        let clipboard = try source.copyingNodes(["a"])
        let destination = try archive("<canvas xmlns='urn:destination'/>")
        let pasted = try destination.applying(
            .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        XCTAssertEqual(try pasted.editorContents().nodes.map(\.id), ["new-a"])
        let root = try XMLDocument(data: pasted.modelXML).rootElement()
        let node = root?.elements(forName: "nodes").first?.elements(forName: "node").first
        XCTAssertEqual(node?.uri, "urn:destination")
        XCTAssertEqual((node?.children?.first as? XMLElement)?.uri ?? "", "")
    }

    func testImportedFragmentRejectsParallelEdgesInEitherDirection() throws {
        let original = try source()
        let xml = String(decoding: original.modelXML, as: UTF8.self)
        for endpoints in [("a", "b"), ("b", "a")] {
            let duplicate = xml.replacingOccurrences(
                of: "</edges>",
                with:
                    "<edge id='duplicate' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' from='\(endpoints.0)' to='\(endpoints.1)'/></edges>"
            )
            XCTAssertThrowsError(try archive(duplicate).copyingNodes(["a", "b"])) {
                XCTAssertEqual($0 as? DocumentError, .invalidNode)
            }
        }
    }

    func testNamespacedPasteWithExplicitIdentitiesIsDeterministic() throws {
        let clipboard = try richSource().copyingNodes(["a", "b"])
        let destination = try source()
        let command = DocumentCommand.pasteNodes(
            clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0.04, z: 0.04))
        let expected = try destination.applying(command).encoded()
        for _ in 0..<5 { XCTAssertEqual(try destination.applying(command).encoded(), expected) }
    }

    func testNamedCutFaceDoesNotCopyAnUnrelatedPartWithTheSameIdentity() throws {
        for preset in ["Quad", "Pentagon", "Hexagon", "Triangle", "UserDefined", "futurePreset"] {
            let source = try archive(
                "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1' cutFace='\(preset)'/><node id='unrelated' partId='\(preset)' x='1' y='0' z='0' radius='.1'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' cutFace='\(preset)'/><part id='\(preset)'/></parts></canvas>"
            )
            let clipboard = try source.copyingNodes(["a"])
            XCTAssertEqual(try clipboard.document.editorContents().nodes.map(\.id), ["a"])
            let pasted = try archive("<canvas/>").applying(
                .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
            let root = try XMLDocument(data: pasted.modelXML).rootElement()
            XCTAssertEqual(
                root?.elements(forName: "parts").first?.elements(forName: "part").first?.attribute(forName: "cutFace")?
                    .stringValue, preset)
        }
    }
    func testPasteRejectsDestinationWithDuplicateComponentContainers() throws {
        let clipboard = try source().copyingNodes(["a"])
        let destination = try archive(
            "<canvas><components/><components><component id='new-component'/></components></canvas>")
        var history = DocumentHistory(document: destination)
        XCTAssertThrowsError(
            try history.apply(
                .pasteNodes(clipboard: clipboard, identities: identities(clipboard), offset: .init(x: 0, y: 0, z: 0)))
        ) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
        XCTAssertEqual(history.document.encoded(), destination.encoded())
        XCTAssertFalse(history.canUndo)
    }

    func testUUIDAliasesCannotBypassClipboardIdentityCollisions() throws {
        let clipboard = try source().copyingNodes(["a"])
        let destination = try source()
        var map = identities(clipboard)
        map["a"] = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        XCTAssertThrowsError(
            try destination.applying(
                .pasteNodes(clipboard: clipboard, identities: map, offset: .init(x: 0, y: 0, z: 0))))
        map = identities(clipboard)
        map["a"] = "{12345678-1234-4234-8234-123456789abc}"
        map["component"] = "12345678-1234-4234-8234-123456789abc"
        XCTAssertThrowsError(
            try destination.applying(
                .pasteNodes(clipboard: clipboard, identities: map, offset: .init(x: 0, y: 0, z: 0))))
        let aliased = try archive(
            "<canvas><nodes><node id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts></canvas>"
        )
        XCTAssertThrowsError(
            try NodeClipboard(document: aliased, selectedNodeIDs: ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]))
    }
    func testUnbracedProfileReferenceFollowsItsBracedPartAndRequiresUUIDReplacement() throws {
        let xml =
            "<canvas><nodes><node id='a' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='0' y='0' z='0' radius='.1' cutFace='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'/><node id='b' partId='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' x='1' y='0' z='0' radius='.1'/></nodes><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/><part id='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}'/></parts></canvas>"
        let clipboard = try archive(xml).copyingNodes(["a"])
        XCTAssertEqual(try clipboard.document.editorContents().nodes.map(\.id), ["a", "b"])
        let map = identities(clipboard)
        let pasted = try archive("<canvas/>").applying(
            .pasteNodes(clipboard: clipboard, identities: map, offset: .init(x: 0, y: 0, z: 0)))
        let root = try XMLDocument(data: pasted.modelXML).rootElement()
        XCTAssertEqual(
            root?.elements(forName: "nodes").first?.elements(forName: "node").first?.attribute(forName: "cutFace")?
                .stringValue, map["{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"])
        var invalid = map
        invalid["{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"] = "not-a-profile-uuid"
        XCTAssertThrowsError(
            try archive("<canvas/>").applying(
                .pasteNodes(clipboard: clipboard, identities: invalid, offset: .init(x: 0, y: 0, z: 0))))
    }

    func testImportedFragmentRequiresEdgePartAndRejectsThreeDistinctIncidentEdges() throws {
        let original = try source()
        let model = try XMLDocument(data: original.modelXML)
        model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge").first?.removeAttribute(
            forName: "partId")
        let missingPart = try archive(model.xmlString(options: [.nodePreserveAll]))
        XCTAssertThrowsError(try NodeClipboard(document: missingPart, selectedNodeIDs: ["a", "b"])) {
            XCTAssertEqual($0 as? DocumentError, .invalidNode)
        }
        XCTAssertThrowsError(try missingPart.copyingNodes(["a", "b"]))
        let branched = try original.applying(
            .addNode(
                id: "d", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", componentID: nil,
                position: .init(x: 1, y: 1, z: 0), radius: 0.1)
        )
        .applying(.addEdge(id: "bd", from: "b", to: "d"))
        XCTAssertThrowsError(try branched.copyingNodes(["a", "b", "c", "d"]))
    }

}
