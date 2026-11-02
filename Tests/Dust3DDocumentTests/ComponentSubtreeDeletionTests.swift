import Dust3DDocument
import Foundation
import XCTest

final class ComponentSubtreeDeletionTests: XCTestCase {
    private let part = "{11111111-1111-4111-8111-111111111111}"
    private let other = "{22222222-2222-4222-8222-222222222222}"
    private func source() throws -> Dust3DDocument {
        let xml = Data(
            """
            <canvas originX='.5' originY='.5' originZ='.5' rigType='Biped' future='canvas'><nodes>
            <node id='n1' partId='\(part)' x='.3' y='.3' z='.5' radius='.1'/><node id='n2' partId='\(part)' x='.3' y='.7' z='.5' radius='.1'/>
            <node id='m1' partId='\(other)' x='.7' y='.3' z='.5' radius='.1'/><node id='m2' partId='\(other)' x='.7' y='.7' z='.5' radius='.1'/></nodes><edges>
            <edge id='inside' partId='\(part)' from='n1' to='n2'/><edge id='remaining' partId='\(other)' from='m1' to='m2'/>
            <edge id='incident' partId='\(other)' from='n2' to='m1'/><edge id='owned' partId='\(part)' from='m1' to='m2'/></edges><parts>
            <part id='\(part)' visible='false' locked='true' disabled='true' xMirrored='true' metallic='.4' future='part'/>
            <part id='\(other)' cutFace='\(part)'/><part id='template' future='unreferenced'/></parts><components>
            <component id='opaque' linkDataType='future' linkData='\(other)' future='owned'><component id='leaf' linkDataType='partId' linkData='\(part)'/><component id='nested'><component id='missing' linkDataType='partId' linkData='absent'/></component></component>
            <component id='instance' linkDataType='partId' linkData='\(part)'/><component id='survivor' wrap='Cloth' wrapBindTo='opaque' future='survives'><component id='other' linkDataType='partId' linkData='\(other)'/><!--keep--></component><component id='empty'/></components>
            <animations><animation id='motion' type='future' node='n1' component='opaque'/></animations><future><node id='n1' partId='\(part)'/></future></canvas>
            """.utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/><asset name='opaque.bin' offset='\(xml.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml + Data([0, 255, 10, 128]))
    }
    private func assertSameGraph(_ left: Dust3DDocument, _ right: Dust3DDocument) throws {
        let a = try left.editorContents()
        let b = try right.editorContents()
        XCTAssertEqual(a.nodes, b.nodes)
        XCTAssertEqual(a.edges, b.edges)
        XCTAssertEqual(a.parts, b.parts)
    }
    func testOpaqueSubtreeRemovalPreservesSharedGraphUntilTheLastKnownInstanceAndNeverInfersOpaqueLinks() throws {
        let original = try source()
        let first = try original.applying(.removeComponentSubtrees(["opaque", "leaf", "opaque"]))
        XCTAssertEqual(try first.components().map(\.id), ["instance", "survivor", "other", "empty"])
        try assertSameGraph(first, original)
        let last = try first.applying(.removeComponentSubtrees(["instance"]))
        let contents = try last.editorContents()
        XCTAssertEqual(contents.parts.map(\.id), [other, "template"])
        XCTAssertEqual(contents.nodes.map(\.id), ["m1", "m2"])
        XCTAssertEqual(contents.edges.map(\.id), ["remaining"])
        XCTAssertEqual(try last.components().map(\.id), ["survivor", "other", "empty"])
        XCTAssertEqual(contents.parts.first?.cutFace, .linkedPart(part))
        XCTAssertEqual(last.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        let xml = try XMLDocument(data: last.modelXML)
        XCTAssertEqual(
            try xml.nodes(forXPath: "/canvas/components/component[@id='survivor']/@wrapBindTo").first?.stringValue,
            "opaque")
        XCTAssertEqual(try xml.nodes(forXPath: "/canvas/animations/animation").first?.stringValue, "")
        XCTAssertEqual(
            (try xml.nodes(forXPath: "/canvas/animations/animation").first as? XMLElement)?.attribute(forName: "node")?
                .stringValue, "n1")
        XCTAssertEqual(try xml.nodes(forXPath: "/canvas/future/node").count, 1)
        XCTAssertTrue(String(decoding: last.modelXML, as: UTF8.self).contains("<!--keep-->"))
    }
    func testWholeBatchIsOneExactUndoAndBothInputsAdvanceWithoutGlobalOrphanCleanup() throws {
        let original = try source()
        var history = DocumentHistory(document: original)
        let preview = history.previewIdentity
        try history.apply(.removeComponentSubtrees(["opaque", "leaf", "instance", "empty"]))
        XCTAssertNotEqual(history.previewIdentity.geometry, preview.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, preview.materials)
        XCTAssertEqual(try history.document.editorContents().parts.map(\.id), [other, "template"])
        let changed = history.document.encoded()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.document.hasSameEditingState(as: original))
        XCTAssertEqual(history.previewIdentity, preview)
        XCTAssertFalse(history.canUndo)
        try history.apply(.removeComponentSubtrees([]))
        XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed)
        XCTAssertEqual(try Dust3DDocument(data: changed).encoded(), changed)
    }
    func testMissingSelectedIDRejectsAllButExistingDanglingLinkedRowCanBeDeletedAsRepair() throws {
        let original = try source()
        XCTAssertThrowsError(try original.applying(.removeComponentSubtrees(["empty", "not-present"]))) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent("not-present"))
        }
        let repaired = try original.applying(.removeComponentSubtrees(["missing"]))
        XCTAssertFalse(try repaired.components().contains { $0.id == "missing" })
        XCTAssertTrue(try repaired.components().contains { $0.id == "nested" })
        try assertSameGraph(repaired, original)
    }
    func testExactUTF8OwnershipAndEveryRequestedIdentityStayDistinctBeforeDeduplication() throws {
        let partID = "cafe\u{301}"
        let ownerID = "owner-cafe\u{301}"
        let missingOwner = "owner-caf\u{e9}"
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='actual' partId='cafe&#769;' x='.3' y='.3' z='.5' radius='.1'/><node id='left' partId='other' x='.6' y='.3' z='.5' radius='.1'/><node id='right' partId='other' x='.6' y='.7' z='.5' radius='.1'/></nodes><edges><edge id='actual-owned' partId='cafe&#769;' from='left' to='right'/><edge id='opaque-owned' partId='caf&#233;' from='left' to='right'/><edge id='actual-incident' partId='other' from='actual' to='left'/></edges><parts><part id='cafe&#769;'/><part id='other' cutFace='caf&#233;'/></parts><components><component id='owner-cafe&#769;' linkDataType='partId' linkData='cafe&#769;'/><component id='dangling' linkDataType='partId' linkData='caf&#233;'/><component id='soft' wrap='Cloth' wrapBindTo='owner-caf&#233;'/></components></canvas>
                """.utf8))
        let removedDangling = try document.applying(.removeComponentSubtrees(["dangling"]))
        XCTAssertTrue(try removedDangling.editorContents().parts.contains { $0.id.utf8.elementsEqual(partID.utf8) })
        let removedActual = try document.applying(.removeComponentSubtrees([ownerID, ownerID]))
        XCTAssertEqual(try removedActual.editorContents().parts.map(\.id), ["other"])
        XCTAssertEqual(try removedActual.editorContents().nodes.map(\.id), ["left", "right"])
        XCTAssertEqual(try removedActual.editorContents().edges.map(\.id), ["opaque-owned"])
        XCTAssertEqual(try removedActual.components().map(\.id), ["dangling", "soft"])
        XCTAssertTrue(try XCTUnwrap(removedActual.components().first?.partID).utf8.elementsEqual("caf\u{e9}".utf8))
        let xml = try XMLDocument(data: removedActual.modelXML)
        let binding = try XCTUnwrap(
            xml.nodes(forXPath: "/canvas/components/component[@id='soft']/@wrapBindTo").first?.stringValue)
        XCTAssertTrue(binding.utf8.elementsEqual(missingOwner.utf8))
        for ids in [[ownerID, missingOwner], [missingOwner, ownerID], [missingOwner]] {
            XCTAssertThrowsError(try document.applying(.removeComponentSubtrees(ids))) { error in
                guard case .missingComponent(let id) = error as? DocumentError else {
                    return XCTFail("Expected missing exact component identity")
                }
                XCTAssertTrue(id.utf8.elementsEqual(missingOwner.utf8))
            }
        }
    }

}
