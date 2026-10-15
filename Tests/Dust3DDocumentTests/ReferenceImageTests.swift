import Dust3DDocument
import Foundation
import XCTest

final class ReferenceImageTests: XCTestCase {
    private func png() throws -> Data {
        try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    }
    private func archive(header: String, payload: Data) throws -> Dust3DDocument {
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + payload)
    }
    private func document(image: Data? = nil, imageType: String = "asset") throws -> Dust3DDocument {
        let model = Data("<canvas future='model'><nodes/></canvas>".utf8)
        let image = try image ?? png()
        let modelOffset = 3 + image.count + 2
        let opaqueOffset = modelOffset + model.count + 3
        let header = """
            <ds3 future='root' xmlns:x='urn:future'><!--retain header-->
            <model name='model.xml' offset='\(modelOffset)' size='\(model.count)' future='model-header'/>
            <\(imageType) name='canvas.png' offset='3' size='\(image.count)' x:future='image'><x:note>keep</x:note></\(imageType)>
            <asset name='empty.bin' offset='6' size='0' future='empty'/>
            <asset name='opaque.bin' offset='\(opaqueOffset)' size='4' future='opaque'/>
            </ds3>
            """
        return try archive(
            header: header,
            payload: Data([0xAA, 0xBB, 0xCC]) + image + Data([0xDE, 0xAD]) + model
                + Data([0xFA, 0xCE, 1, 0, 255, 10, 128, 0xFE, 0xED]))
    }
    private func header(_ document: Dust3DDocument) throws -> XMLElement {
        let bytes = document.encoded()
        let lineEnd = try XCTUnwrap(bytes.firstIndex(of: 10))
        var lineBytes = Data(bytes[..<lineEnd])
        if lineBytes.starts(with: [0xD3, 0x3D]) { lineBytes.removeFirst(2) }
        let line = try XCTUnwrap(String(data: lineBytes, encoding: .utf8))
        let offset = try XCTUnwrap(Int(try XCTUnwrap(line.split(whereSeparator: { $0.isWhitespace }).last)))
        return try XCTUnwrap(XMLDocument(data: bytes[(lineEnd + 1)..<offset]).rootElement())
    }
    func testExistingImageAndNoOpCommandsPreserveEveryByte() throws {
        let original = try document()
        XCTAssertEqual(original.referenceImagePNG, try png())
        XCTAssertEqual(try original.applying(.setReferenceImagePNG(png())).encoded(), original.encoded())
        let blank = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        XCTAssertNil(blank.referenceImagePNG)
        XCTAssertEqual(try blank.applying(.setReferenceImagePNG(nil)).encoded(), blank.encoded())
    }
    func testReplacementPreservesModelAssetsMetadataAndPayloadGaps() throws {
        let original = try document()
        let replacement = try png() + Data([1, 2, 3])
        let next = try original.applying(.setReferenceImagePNG(replacement))
        XCTAssertEqual(next.referenceImagePNG, replacement)
        XCTAssertEqual(next.modelXML, original.modelXML)
        XCTAssertEqual(next.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        XCTAssertEqual(next.asset(named: "empty.bin"), Data())
        let root = try header(next)
        XCTAssertEqual(root.attribute(forName: "future")?.stringValue, "root")
        let image = try XCTUnwrap(
            root.elements(forName: "asset").first { $0.attribute(forName: "name")?.stringValue == "canvas.png" })
        XCTAssertEqual(image.attribute(forName: "x:future")?.stringValue, "image")
        XCTAssertEqual(image.elements(forName: "x:note").first?.stringValue, "keep")
        for sentinel in [Data([0xAA, 0xBB, 0xCC]), Data([0xDE, 0xAD]), Data([0xFA, 0xCE, 1]), Data([0xFE, 0xED])] {
            XCTAssertNotNil(next.encoded().range(of: sentinel))
        }
        let restored = try Dust3DDocument(data: next.encoded())
        XCTAssertEqual(restored.referenceImagePNG, replacement)
    }
    func testRemovalReanchorsEmptyEntriesAndRetainsUnrelatedBytes() throws {
        let original = try document()
        let next = try original.applying(.setReferenceImagePNG(nil))
        XCTAssertNil(next.referenceImagePNG)
        XCTAssertEqual(next.modelXML, original.modelXML)
        XCTAssertEqual(next.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        XCTAssertEqual(next.asset(named: "empty.bin"), Data())
        XCTAssertNotNil(next.encoded().range(of: Data([0xAA, 0xBB, 0xCC, 0xDE, 0xAD])))
        XCTAssertNotNil(next.encoded().range(of: Data([0xFE, 0xED])))
    }
    func testAdditionRemovalAndReplacementAreUndoableInsideTransactions() throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        var history = DocumentHistory(document: original)
        try history.beginTransaction()
        try history.apply(.setReferenceImagePNG(png()))
        try history.endTransaction()
        let added = history.document
        XCTAssertEqual(added.referenceImagePNG, try png())
        XCTAssertTrue(history.canUndo)
        XCTAssertTrue(history.isDirty)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), added.encoded())
        try history.beginTransaction()
        try history.apply(.setReferenceImagePNG(nil))
        try history.endTransaction()
        XCTAssertNil(history.document.referenceImagePNG)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), added.encoded())
    }
    func testNetZeroAssetTransactionsRestoreExactOriginalAndPreserveRedo() throws {
        let original = try document()
        var history = DocumentHistory(document: original)
        try history.apply(.setReferenceImagePNG(nil))
        XCTAssertTrue(history.undo())
        try history.beginTransaction()
        try history.apply(.setReferenceImagePNG(png() + Data([1])))
        try history.apply(.setReferenceImagePNG(png()))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
        let blank = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        var empty = DocumentHistory(document: blank)
        try empty.beginTransaction()
        try empty.apply(.setReferenceImagePNG(png()))
        try empty.apply(.setReferenceImagePNG(nil))
        try empty.endTransaction()
        XCTAssertEqual(empty.document.encoded(), blank.encoded())
        XCTAssertFalse(empty.canUndo)
    }
    func testInvalidAndOversizedImageCommandsAreAtomic() throws {
        let original = try document()
        var history = DocumentHistory(document: original)
        for invalid in [Data(), Data("not PNG".utf8)] {
            XCTAssertThrowsError(try history.apply(.setReferenceImagePNG(invalid))) {
                XCTAssertEqual($0 as? DocumentError, .invalidReferenceImage)
            }
        }
        XCTAssertThrowsError(try history.apply(.setReferenceImagePNG(Data(repeating: 0, count: 32 * 1024 * 1024 + 1))))
        { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        var bounded = DocumentHistory(document: original, maximumUndoBytes: original.encoded().count)
        XCTAssertThrowsError(try bounded.apply(.setReferenceImagePNG(png() + Data(repeating: 0, count: 1024))))
        XCTAssertEqual(bounded.document.encoded(), original.encoded())
        XCTAssertFalse(bounded.canUndo)
    }
    func testReservedNameConflictAndArchiveItemLimitRejectAddition() throws {
        let conflict = try document(imageType: "opaque")
        XCTAssertNil(conflict.referenceImagePNG)
        XCTAssertThrowsError(try conflict.applying(.setReferenceImagePNG(png()))) {
            XCTAssertEqual($0 as? DocumentError, .conflictingAsset("canvas.png"))
        }
        XCTAssertThrowsError(try conflict.applying(.setReferenceImagePNG(nil)))
        let model = Data("<canvas/>".utf8)
        let items = (0..<9999).map { "<asset name='a\($0)' offset='0' size='0'/>" }.joined()
        let full = try archive(
            header: "<ds3><model name='model.xml' offset='0' size='\(model.count)'/>\(items)</ds3>", payload: model)
        XCTAssertThrowsError(try full.applying(.setReferenceImagePNG(png()))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
    }

    func testHeaderGrowthLimitAndTransactionCancellationPreserveOriginal() throws {
        let model = Data("<canvas/>".utf8)
        let metadata = String(repeating: "x", count: 1024 * 1024 - 130)
        let bounded = try archive(
            header: "<ds3><!--\(metadata)--><model name='model.xml' offset='0' size='\(model.count)'/></ds3>",
            payload: model)
        XCTAssertThrowsError(try bounded.applying(.setReferenceImagePNG(png()))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        let original = try document()
        var history = DocumentHistory(document: original)
        try history.beginTransaction()
        try history.apply(.setReferenceImagePNG(nil))
        history.cancelTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.isDirty)
    }

    func testModelOnlyAndMixedTransactionsWithLargeImageKeepCorrectHistory() throws {
        let image = try png() + Data(repeating: 0, count: 4 * 1024 * 1024)
        let original = try document(image: image).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        var history = DocumentHistory(document: original)
        let moved = NodeUpdate(id: "a", value: .init(position: .init(x: 0.5, y: 0, z: 0), radius: 0.1))
        let restored = NodeUpdate(id: "a", value: .init(position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        try history.beginTransaction()
        try history.apply(.setNodes([moved]))
        try history.apply(.setNodes([restored]))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        try history.beginTransaction()
        try history.apply(.setNodes([moved]))
        try history.apply(.setReferenceImagePNG(png()))
        try history.endTransaction()
        XCTAssertEqual(try history.document.node(id: "a").position.x, 0.5)
        XCTAssertEqual(history.document.referenceImagePNG, try png())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
    }
}
