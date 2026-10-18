import Foundation
import XCTest

@testable import Dust3DDocument

final class NamespaceTransferTests: XCTestCase {
    private func archive(
        model: String, namespaces: String = "", assetCount: Int = 0, assetMetadata: String = ""
    ) throws -> Dust3DDocument {
        let payload = Data(model.utf8)
        let assets = (0..<assetCount).map {
            "<asset name='opaque-\($0)' offset='\(payload.count + $0)' size='1' \(assetMetadata)/>"
        }.joined()
        let header = "<ds3 \(namespaces)><model name='model.xml' offset='0' size='\(payload.count)'/>\(assets)</ds3>"
        let prefix = "DUST3D 1.0 xml "
        let bytes =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + payload + Data(repeating: 42, count: assetCount)
        return try Dust3DDocument(data: bytes)
    }

    private func model(namespaces: String = "", nodeCount: Int = 1) -> String {
        let nodes = (0..<nodeCount).map {
            "<node id='n\($0)' partId='p' x='.5' y='.5' z='.5' radius='.1'><future/></node>"
        }.joined()
        return
            "<canvas \(namespaces)><nodes>\(nodes)</nodes><edges/><parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
    }

    private func assertPasteRejectsAtomically(
        _ source: Dust3DDocument, nodeCount: Int = 1, destination: Dust3DDocument? = nil
    ) throws {
        let original = try destination ?? Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let clipboard = try NodeClipboard(document: source, selectedNodeIDs: Set((0..<nodeCount).map { "n\($0)" }))
        let identities = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "fresh-" + $0) })
        var history = DocumentHistory(document: original)
        XCTAssertThrowsError(
            try history.apply(
                .pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0, z: 0)))
        ) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testShouldRejectCumulativeClipboardNamespaceBindingsBeforePublishing() throws {
        let namespaces = (0..<501).map { "xmlns:q\($0)='urn:namespace:\($0)'" }.joined(separator: " ")
        try assertPasteRejectsAtomically(archive(model: model(namespaces: namespaces, nodeCount: 200)), nodeCount: 200)
    }

    func testShouldRejectCumulativeAssetHeaderNamespaceBindingsWithTypedLimitError() throws {
        let namespaces = (0..<501).map { "xmlns:q\($0)='urn:namespace:\($0)'" }.joined(separator: " ")
        try assertPasteRejectsAtomically(archive(model: model(), namespaces: namespaces, assetCount: 201))
    }

    func testShouldRejectCumulativeAssetNamespacePayloadBeforeHeaderEncoding() throws {
        let namespaces = "xmlns:q='urn:" + String(repeating: "x", count: 80 * 1024) + "'"
        try assertPasteRejectsAtomically(archive(model: model(), namespaces: namespaces, assetCount: 220))
    }
    func testShouldShareOneBudgetAcrossGraphAndAssetTransfers() throws {
        let namespaces = (0..<251).map { "xmlns:q\($0)='urn:namespace:\($0)'" }.joined(separator: " ")
        try assertPasteRejectsAtomically(
            archive(model: model(namespaces: namespaces, nodeCount: 150), namespaces: namespaces, assetCount: 150),
            nodeCount: 150)
    }

    func testShouldBudgetExplicitDefaultNamespaceReplacementAsWellAsPreservation() throws {
        let sourceURI = "urn:source:" + String(repeating: "x", count: 1024 * 1024)
        let targetURI = "urn:target:" + String(repeating: "y", count: 1024 * 1024)
        let source = try archive(
            model: model(namespaces: "xmlns='\(sourceURI)'", nodeCount: 8).replacingOccurrences(
                of: "<future/>", with: ""))
        let original = try archive(model: "<canvas xmlns='\(targetURI)'><nodes/><edges/><parts/><components/></canvas>")
        let clipboard = try NodeClipboard(document: source, selectedNodeIDs: Set((0..<8).map { "n\($0)" }))
        let identities = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "fresh-" + $0) })
        XCTAssertThrowsError(
            try original.applying(
                .pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0, z: 0)))
        ) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
    }

    func testShouldPreserveConflictingNamespaceBindingsQNameValuesAssetsAndExactHistoryWithinBudget() throws {
        let source = try archive(
            model: model(namespaces: "xmlns='urn:model-source' xmlns:q='urn:model-value'")
                .replacingOccurrences(of: "<future/>", with: "<future q:kind='q:Marker'/>"),
            namespaces: "xmlns:q='urn:header-source'", assetCount: 1, assetMetadata: "q:kind='q:Asset'")
        let original = try archive(
            model:
                "<canvas xmlns='urn:target' xmlns:q='urn:destination'><nodes/><edges/><parts/><components/></canvas>",
            namespaces: "xmlns:q='urn:header-target'")
        let sourceBytes = source.encoded()
        let clipboard = try NodeClipboard(document: source, selectedNodeIDs: ["n0"])
        let identities = Dictionary(uniqueKeysWithValues: clipboard.identifiers.map { ($0, "fresh-" + $0) })
        var history = DocumentHistory(document: original)
        try history.apply(.pasteNodes(clipboard: clipboard, identities: identities, offset: .init(x: 0, y: 0, z: 0)))
        let changed = history.document
        let model = try XMLDocument(data: changed.modelXML)
        let root = try XCTUnwrap(model.rootElement())
        let node = try XCTUnwrap(DocumentXML.semanticElements(model).first { $0.name == "node" })
        XCTAssertEqual(node.uri, "urn:target")
        let opaque = try XCTUnwrap(node.children?.compactMap { $0 as? XMLElement }.first)
        XCTAssertEqual(opaque.uri, "urn:model-source")
        XCTAssertEqual(opaque.attribute(forName: "q:kind")?.uri, "urn:model-value")
        XCTAssertEqual(opaque.attribute(forName: "q:kind")?.stringValue, "q:Marker")
        XCTAssertEqual(root.namespaces?.first { $0.name == "q" }?.stringValue, "urn:destination")
        let bytes = changed.encoded()
        let lineEnd = try XCTUnwrap(bytes.firstIndex(of: 10))
        let offsetText = try XCTUnwrap(
            String(decoding: bytes[..<lineEnd], as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).last)
        let offset = try XCTUnwrap(Int(offsetText))
        let header = try XMLDocument(data: Data(bytes[(lineEnd + 1)..<offset]))
        let asset = try XCTUnwrap(header.rootElement()?.elements(forName: "asset").first)
        XCTAssertEqual(asset.attribute(forName: "q:kind")?.uri, "urn:header-source")
        XCTAssertEqual(asset.attribute(forName: "q:kind")?.stringValue, "q:Asset")
        XCTAssertEqual(changed.asset(named: "opaque-0"), Data([42]))
        XCTAssertEqual(source.encoded(), sourceBytes)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
    }

    func testShouldBudgetNamespaceMaterializationWhenComparingSharedAssets() throws {
        let namespaces = (0..<501).map { "xmlns:q\($0)='urn:namespace:\($0)'" }.joined(separator: " ")
        let source = try archive(model: model(), namespaces: namespaces, assetCount: 101)
        let destination = try archive(
            model: "<canvas><nodes/><edges/><parts/><components/></canvas>",
            namespaces: namespaces, assetCount: 101)
        try assertPasteRejectsAtomically(source, destination: destination)
    }

}
