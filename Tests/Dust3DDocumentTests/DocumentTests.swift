import Dust3DDocument
import Foundation
import XCTest

final class DocumentTests: XCTestCase {
    private let nodeID = "{11111111-1111-4111-8111-111111111111}"

    private func archive(items: String, payload: Data) -> Data {
        let header = "<ds3>\(items)</ds3>"
        let prefix = "DUST3D 1.0 xml "
        let offset = prefix.utf8.count + 12 + header.utf8.count
        return Data((prefix + String(format: "%010d\r\n", offset) + header).utf8) + payload
    }

    func testArchiveBoundsNamesAndModelAmbiguityAreRejected() {
        let model = Data("<canvas/>".utf8)
        let valid = "<model name='model.xml' offset='0' size='\(model.count)'/>"
        for items in [
            "", valid + valid,
            "<image name='image' offset='0' size='0'/>",
            "<model name='model.xml' offset='999' size='1'/>",
            "<model name='model.xml' offset='0' size='999'/>",
            "<model name='model.xml' offset='-1' size='1'/>",
            "<model name='model.xml' offset='0' size='18446744073709551616'/>",
            "<model name='model.xml' size='1'/>",
            valid + "<image name='overlap' offset='1' size='1'/>",
            valid + "<model name='second.xml' offset='\(model.count)' size='0'/>",
        ] {
            XCTAssertThrowsError(try Dust3DDocument(data: archive(items: items, payload: model)), items)
        }
        for header in ["DUST3D 2.0 xml 40\n", "DUST3D 1.0 xml -1\n", "wrong 1.0 xml 40\n"] {
            XCTAssertThrowsError(try Dust3DDocument(data: Data(header.utf8)))
        }
    }

    func testEmptyAssetInsideModelRetainsValidOffsetWhenModelShrinks() throws {
        let xml =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?><canvas><nodes><node id='\(nodeID)' x='00000000001000000' y='00000000001000000' z='00000000001000000' radius='00000000001000000'/></nodes></canvas>"
        let model = Data(xml.utf8)
        let items =
            "<model name='model.xml' offset='0' size='\(model.count)'/><image name='empty' offset='\(model.count - 1)' size='0'/>"
        let bytes = archive(items: items, payload: model)
        let document = try Dust3DDocument(data: bytes)
        XCTAssertEqual(document.encoded(), bytes)
        let edited = try document.applying(.setNode(id: nodeID, position: .init(x: 0, y: 0, z: 0), radius: 0))
        XCTAssertLessThan(edited.modelXML.count, model.count)
        XCTAssertEqual(edited.asset(named: "empty"), Data())
        XCTAssertEqual(try Dust3DDocument(data: edited.encoded()).asset(named: "empty"), Data())
    }

    func testParserResourceLimitsAreEnforcedBeforeInterpretation() {
        XCTAssertThrowsError(try Dust3DDocument(data: Data(count: 256 * 1024 * 1024 + 1)))
        let large = Data(count: 16 * 1024 * 1024 + 1)
        XCTAssertThrowsError(
            try Dust3DDocument(
                data: archive(items: "<model name='m' offset='0' size='\(large.count)'/>", payload: large)))
        let items = (0...10_000).map { "<image name='\($0)' offset='0' size='0'/>" }.joined()
        XCTAssertThrowsError(try Dust3DDocument(data: archive(items: items, payload: Data())))
        let largeHeader = String(repeating: " ", count: 1024 * 1024 + 1)
        XCTAssertThrowsError(try Dust3DDocument(data: archive(items: largeHeader, payload: Data())))
    }

    func testUnsupportedXMLAndInvalidNumericNodesAreRejected() throws {
        for xml in [
            "<other/>", "<canvas>", "<canvas>\0</canvas>", "<canvas><nodes/><nodes/></canvas>",
            "<canvas><nodes><node/></nodes></canvas>",
        ] {
            XCTAssertThrowsError(try Dust3DDocument(data: fixture(model: xml)))
        }
        for attributes in ["x='nan' y='0' z='0' radius='1'", "x='0' y='0' z='0' radius='-1'", "y='0' z='0' radius='1'"]
        {
            let xml = "<canvas><nodes><node id='\(nodeID)' \(attributes)/></nodes></canvas>"
            let document = try Dust3DDocument(data: fixture(model: xml))
            XCTAssertThrowsError(try document.node(id: nodeID))
        }
    }

    private func fixture(model: String? = nil) -> Data {
        let xml =
            model ?? """
                <?xml version="1.0"?><canvas future="keep"><!--keep comment--><nodes>
                <node id="\(nodeID)" x="1" y="2" z="3" radius="0.5" futureNode="keep"/>
                </nodes><futureElement value="retained"/></canvas>
                """
        let payload = Data(xml.utf8)
        let header = """
            <?xml version="1.0"?><ds3 futureHeader="keep"><model name="model.xml" offset="0" size="\(payload.count)" futureItem="keep"/><image name="future.bin" offset="\(payload.count + 3)" size="4"/></ds3>
            """
        let prefix = "DUST3D 1.0 xml "
        let offset = prefix.utf8.count + 12 + header.utf8.count
        var result = Data((prefix + String(format: "%010d\r\n", offset) + header).utf8)
        result.append(payload)
        result.append(contentsOf: [9, 8, 7, 0, 255, 128, 1, 6, 5])
        return result
    }

    func testUnchangedArchiveRoundTripsByteForByte() throws {
        let bytes = fixture()
        let document = try Dust3DDocument(data: bytes)
        XCTAssertEqual(document.encoded(), bytes)
        XCTAssertNil(document.asset(named: "missing"))
    }

    func testEditCannotGrowModelPastXMLLimit() throws {
        let start = "<canvas><nodes><node id='\(nodeID)' x='1' y='2' z='3' radius='0.5'/></nodes><future>"
        let end = "</future></canvas>"
        let remaining = 16 * 1024 * 1024 - start.utf8.count - end.utf8.count
        let unit = "<!--" + String(repeating: "a", count: 1017) + "-->"
        let padding = String(repeating: unit, count: remaining / 1024) + String(repeating: " ", count: remaining % 1024)
        let document = try Dust3DDocument(data: fixture(model: start + padding + end))
        XCTAssertThrowsError(
            try document.applying(.setNode(id: nodeID, position: .init(x: 4, y: 5, z: 6), radius: 0.75))
        ) { error in
            XCTAssertEqual(error as? DocumentError, .limitExceeded)
        }
    }

    func testNodeEditPreservesUnknownXMLAssetsAndPayloadGaps() throws {
        let original = try Dust3DDocument(data: fixture())
        let edited = try original.applying(.setNode(id: nodeID, position: .init(x: 4, y: 5, z: 6), radius: 0.75))
        let reopened = try Dust3DDocument(data: edited.encoded())
        XCTAssertEqual(try reopened.node(id: nodeID), .init(position: .init(x: 4, y: 5, z: 6), radius: 0.75))
        XCTAssertEqual(reopened.asset(named: "future.bin"), Data([0, 255, 128, 1]))
        XCTAssertEqual(edited.encoded().suffix(9), original.encoded().suffix(9))
        XCTAssertTrue(String(decoding: reopened.modelXML, as: UTF8.self).contains("futureNode=\"keep\""))
        XCTAssertTrue(String(decoding: reopened.modelXML, as: UTF8.self).contains("futureElement"))
        XCTAssertTrue(String(decoding: reopened.modelXML, as: UTF8.self).contains("keep comment"))
        XCTAssertTrue(String(decoding: reopened.encoded(), as: UTF8.self).contains("futureHeader=\"keep\""))
        XCTAssertTrue(String(decoding: reopened.encoded(), as: UTF8.self).contains("futureItem=\"keep\""))
    }

    func testInvalidAndUnknownNodeCommandsDoNotChangeDocument() throws {
        let document = try Dust3DDocument(data: fixture())
        XCTAssertThrowsError(
            try document.applying(.setNode(id: nodeID, position: .init(x: .nan, y: 0, z: 0), radius: 1)))
        XCTAssertThrowsError(try document.applying(.setNode(id: nodeID, position: .init(x: 0, y: 0, z: 0), radius: -1)))
        XCTAssertThrowsError(
            try document.applying(.setNode(id: "missing", position: .init(x: 0, y: 0, z: 0), radius: 1)))
        XCTAssertEqual(document.encoded(), fixture())
    }

    func testMalformedArchivesAndExternalEntitiesAreRejected() {
        XCTAssertThrowsError(try Dust3DDocument(data: Data()))
        XCTAssertThrowsError(try Dust3DDocument(data: Data("DUST3D 1.0 xml 1\n<ds3/>".utf8)))
        XCTAssertThrowsError(
            try Dust3DDocument(
                data: fixture(model: "<!DOCTYPE canvas [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><canvas>&x;</canvas>"))
        )
        XCTAssertThrowsError(
            try Dust3DDocument(
                data: fixture(model: "<canvas><nodes><node id='same'/><node id='same'/></nodes></canvas>")))
        XCTAssertThrowsError(try Dust3DDocument(data: Data([255, 10])))
        let deep = String(repeating: "<a>", count: 129) + String(repeating: "</a>", count: 129)
        XCTAssertThrowsError(try Dust3DDocument(data: fixture(model: deep)))
    }

    func testUndoRedoRestoresExactBytesAndSavepoint() throws {
        var history = DocumentHistory(document: try Dust3DDocument(data: fixture()))
        try history.apply(.setNode(id: nodeID, position: .init(x: 9, y: 2, z: 3), radius: 0.5))
        let changed = history.document.encoded()
        XCTAssertTrue(history.isDirty)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), fixture())
        XCTAssertFalse(history.isDirty)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed)
        history.markSaved(history.document)
        XCTAssertFalse(history.isDirty)
        XCTAssertTrue(history.undo())
        XCTAssertTrue(history.isDirty)
    }

    func testOlderSaveCompletionDoesNotMarkNewerEditsClean() throws {
        var history = DocumentHistory(document: try Dust3DDocument(data: fixture()))
        try history.apply(.setNode(id: nodeID, position: .init(x: 4, y: 2, z: 3), radius: 0.5))
        let written = history.document
        try history.apply(.setNode(id: nodeID, position: .init(x: 5, y: 2, z: 3), radius: 0.5))
        history.markSaved(written)
        XCTAssertTrue(history.isDirty)
        XCTAssertTrue(history.undo())
        XCTAssertFalse(history.isDirty)
    }

    func testGestureTransactionCoalescesAndCancelRestores() throws {
        var history = DocumentHistory(document: try Dust3DDocument(data: fixture()))
        try history.beginTransaction()
        for x in 4...6 {
            try history.apply(.setNode(id: nodeID, position: .init(x: Double(x), y: 2, z: 3), radius: 0.5))
        }
        try history.endTransaction()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), fixture())
        XCTAssertFalse(history.undo())
        XCTAssertTrue(history.redo())
        let committed = history.document.encoded()
        try history.beginTransaction()
        try history.apply(.setNode(id: nodeID, position: .init(x: 10, y: 2, z: 3), radius: 0.5))
        history.cancelTransaction()
        XCTAssertEqual(history.document.encoded(), committed)
        XCTAssertThrowsError(try history.endTransaction())
    }

    func testFailedCommandsAndEmptyTransactionsPreserveRedo() throws {
        var history = DocumentHistory(document: try Dust3DDocument(data: fixture()))
        try history.apply(.setNode(id: nodeID, position: .init(x: 4, y: 2, z: 3), radius: 0.5))
        XCTAssertTrue(history.undo())
        try history.beginTransaction()
        XCTAssertThrowsError(try history.beginTransaction())
        XCTAssertThrowsError(try history.apply(.setNode(id: "missing", position: .init(x: 0, y: 0, z: 0), radius: 1)))
        XCTAssertFalse(history.undo())
        try history.endTransaction()
        XCTAssertTrue(history.redo())
    }

    func testNewEditClearsRedoAndHistoryLimitsAreEnforced() throws {
        let original = try Dust3DDocument(data: fixture())
        var history = DocumentHistory(document: original, maximumEntries: 1)
        for x in 4...5 {
            try history.apply(.setNode(id: nodeID, position: .init(x: Double(x), y: 2, z: 3), radius: 0.5))
        }
        XCTAssertTrue(history.undo())
        XCTAssertFalse(history.undo())
        try history.apply(.setNode(id: nodeID, position: .init(x: 8, y: 2, z: 3), radius: 0.5))
        XCTAssertFalse(history.redo())
        var limited = DocumentHistory(document: original, maximumUndoBytes: 1)
        XCTAssertThrowsError(try limited.apply(.setNode(id: nodeID, position: .init(x: 8, y: 2, z: 3), radius: 0.5)))
        XCTAssertEqual(limited.document.encoded(), original.encoded())
        XCTAssertFalse(limited.canUndo)
        XCTAssertFalse(limited.canRedo)
    }

    func testArchiveByteBudgetTrimsFurthestRedoState() throws {
        let original = try Dust3DDocument(data: fixture())
        let command = DocumentCommand.setNode(id: nodeID, position: .init(x: 1_000_000, y: 2, z: 3), radius: 0.5)
        let first = try original.applying(command)
        var history = DocumentHistory(
            document: original, maximumUndoBytes: original.encoded().count + first.encoded().count)
        try history.apply(command)
        try history.apply(.setNode(id: nodeID, position: .init(x: 4, y: 2, z: 3), radius: 0.5))
        XCTAssertTrue(history.undo())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.canRedo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), first.encoded())
        XCTAssertFalse(history.canRedo)
    }

    func testNoOpCommandDoesNotCreateHistory() throws {
        let original = try Dust3DDocument(data: fixture())
        var history = DocumentHistory(document: original)
        history.cancelTransaction()
        try history.apply(.setNode(id: nodeID, position: .init(x: 1, y: 2, z: 3), radius: 0.5))
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testNetZeroGestureRestoresOriginalBytesAndPreservesRedo() throws {
        var history = DocumentHistory(document: try Dust3DDocument(data: fixture()))
        try history.apply(.setNode(id: nodeID, position: .init(x: 4, y: 2, z: 3), radius: 0.5))
        XCTAssertTrue(history.undo())
        try history.beginTransaction()
        try history.apply(.setNode(id: nodeID, position: .init(x: 5, y: 2, z: 3), radius: 0.5))
        try history.apply(.setNode(id: nodeID, position: .init(x: 1, y: 2, z: 3), radius: 0.5))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), fixture())
        XCTAssertFalse(history.isDirty)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
    }

    @MainActor func testAtomicFileRoundTripAndFailedSaveRetainsOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = DocumentFileService()
        let file = directory.appendingPathComponent("model.ds3")
        let document = try Dust3DDocument(data: fixture())
        try await service.save(document, to: file)
        let loaded = try await service.load(from: file)
        XCTAssertEqual(loaded.encoded(), document.encoded())
        do {
            try await service.save(document, to: file.appendingPathComponent("not-a-directory.ds3"))
            XCTFail("Invalid destination accepted")
        } catch {
            XCTAssertEqual(try Data(contentsOf: file), document.encoded())
        }
    }

    @MainActor func testMissingFileAndCancellationKeepUnderlyingErrors() async throws {
        let service = DocumentFileService()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await service.load(from: missing)
            XCTFail("Missing file accepted")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
        let task = Task { try await service.load(from: missing) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled load succeeded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
