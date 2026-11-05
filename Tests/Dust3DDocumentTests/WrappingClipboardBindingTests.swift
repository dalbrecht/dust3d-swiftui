import Dust3DDocument
import Foundation
import XCTest

final class WrappingClipboardBindingTests: XCTestCase {
    private func source(binding: String = "body", bodyID: String = "body") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='n' partId='p' x='.3' y='.5' z='.5' radius='.1'/><node id='m' partId='q' x='.7' y='.5' z='.5' radius='.1'/><node id='outside' partId='r' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p'/><part id='q'/><part id='r'/></parts><components><component id='outer' future='keep'><component id='garment' wrap='Cloth' wrapBindTo='\(binding)' wrapPattern='Future' future='body'><component id='gc' linkDataType='partId' linkData='p'/></component><component id='\(bodyID)'><component id='bc' linkDataType='partId' linkData='q'/></component><component id='drop'><component id='dc' linkDataType='partId' linkData='r'/></component></component></components></canvas>
                """.utf8))
    }
    private func component(_ document: Dust3DDocument, id: String) throws -> XMLElement {
        let xml = try XMLDocument(data: document.modelXML)
        func walk(_ parent: XMLElement) -> XMLElement? {
            if parent.name == "component", parent.attribute(forName: "id")?.stringValue == id { return parent }
            for child in (parent.children ?? []).compactMap({ $0 as? XMLElement }) {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return try XCTUnwrap(xml.rootElement().flatMap(walk))
    }
    private func binding(_ document: Dust3DDocument, id: String) throws -> String? {
        try component(document, id: id).attribute(forName: "wrapBindTo")?.stringValue
    }
    func testInternalCopiedTargetRemapsOnceAcrossSameAndCrossDocumentPasteWithNestedPruning() throws {
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0])
        let original = try source().applying(.setReferenceImagePNG(png))
        let clipboard = try original.copyingNodes(["n", "m"])
        XCTAssertEqual(clipboard.selectedNodeIDs, ["n", "m"])
        XCTAssertFalse(clipboard.identifiers.contains("drop"))
        var identities = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "new-" + $0) })
        // Simultaneous substitution: body->new-body must not be mapped again via another original identity.
        identities["garment"] = "new-garment"
        for destination in [
            original,
            try Dust3DDocument(
                snapshotXML: Data("<canvas><components><component id='body'/></components></canvas>".utf8)),
        ] {
            var history = DocumentHistory(document: destination)
            try history.apply(
                .pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0, z: 0)))
            let pasted = history.document
            XCTAssertEqual(pasted.referenceImagePNG, png)
            XCTAssertEqual(try binding(pasted, id: "new-garment"), "new-body")
            let garment = try component(pasted, id: "new-garment")
            XCTAssertEqual(garment.attribute(forName: "wrapPattern")?.stringValue, "Future")
            XCTAssertEqual(garment.attribute(forName: "future")?.stringValue, "body")
            XCTAssertEqual(try binding(Dust3DDocument(data: pasted.encoded()), id: "new-garment"), "new-body")
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), destination.encoded())
            XCTAssertFalse(history.canUndo)
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), pasted.encoded())
        }
    }
    func testExternalAndMissingOpaqueBindingStayExactWhenOnlyGarmentIsCopied() throws {
        for target in ["body", "missing", " future body "] {
            let original = try source(binding: target)
            let clipboard = try original.copyingNodes(["n"])
            XCTAssertFalse(clipboard.identifiers.contains("body"))
            XCTAssertEqual(Set(clipboard.identifiers), ["n", "p", "outer", "garment", "gc"])
            let ids = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "new-" + $0) })
            for destination in [
                original,
                try Dust3DDocument(
                    snapshotXML: Data("<canvas><components><component id='body'/></components></canvas>".utf8)),
            ] {
                let pasted = try destination.applying(
                    .pasteNodes(clipboard: clipboard, identities: ids, offset: .init(x: 0, y: 0, z: 0)))
                XCTAssertEqual(try binding(pasted, id: "new-garment"), target)
                XCTAssertNotEqual(try binding(pasted, id: "new-garment"), "new-garment")
            }
        }
    }
    func testUUIDBraceAliasesRemapButCaseDistinctAndOpaqueReferencesStayExact() throws {
        let body = "{ABCDEFAB-1234-4234-8234-ABCDEFABCDEF}"
        let original = try source(binding: body, bodyID: body)
        let clipboard = try original.copyingNodes(["n", "m"])
        let ids = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "new-" + $0) })
        for (target, expected) in [
            (String(body.dropFirst().dropLast()), "new-" + body), (body.lowercased(), body.lowercased()),
            ("opaque body", "opaque body"),
        ] {
            let adjusted = try source(binding: target, bodyID: body)
            let fragment = try adjusted.copyingNodes(["n", "m"])
            let pasted = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
                .pasteNodes(clipboard: fragment, identities: ids, offset: .init(x: 0, y: 0, z: 0)))
            XCTAssertEqual(try binding(pasted, id: "new-garment"), expected)
        }
    }
    func testBindingReplacementIsSimultaneousNotRecursive() throws {
        let clipboard = try source().copyingNodes(["n", "m"])
        var ids = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "new-" + $0) })
        ids["body"] = "outer"
        let pasted = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .pasteNodes(clipboard: clipboard, identities: ids, offset: .init(x: 0, y: 0, z: 0)))
        XCTAssertEqual(try binding(pasted, id: "new-garment"), "outer")
    }

    func testCopiedBodyDoesNotRetargetByteDistinctExternalBinding() throws {
        let actual = "cafe\u{301}"
        let external = "caf\u{e9}"
        for target in [actual, external] {
            let original = try source(binding: target, bodyID: actual)
            let clipboard = try original.copyingNodes(["n", "m"])
            let ids = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "new-" + $0) })
            var history = DocumentHistory(document: original)
            try history.apply(.pasteNodes(clipboard: clipboard, identities: ids, offset: .init(x: 0, y: 0, z: 0)))
            let expected = target.utf8.elementsEqual(actual.utf8) ? "new-" + actual : external
            let value = try XCTUnwrap(binding(history.document, id: "new-garment"))
            XCTAssertTrue(value.utf8.elementsEqual(expected.utf8))
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), original.encoded())
        }
    }

}
