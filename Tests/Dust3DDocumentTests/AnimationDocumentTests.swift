import Foundation
import XCTest

@testable import Dust3DDocument

final class AnimationDocumentTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas future='retain'><nodes/><edges/><parts/><components/>
                <animations future='catalog'><animation id='a' name='Idle &amp; rest' type='future-type' duration='1.00' surfaceMaterial='Stone' future='keep'><opaque value='retain'/></animation><!--retain comment--></animations>
                <opaqueRoot value='retain'/></canvas>
                """.utf8))
    }

    func testReadsUnknownStoredIntentWithoutChangingArchiveOrClaimingPlayback() throws {
        let source = try document()
        let before = source.encoded()
        let rows = try source.animations()
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.id, "a")
        XCTAssertEqual(row.name, "Idle & rest")
        XCTAssertEqual(row.type, "future-type")
        XCTAssertEqual(row.parameter(named: "duration"), "1.00")
        XCTAssertEqual(row.parameter(named: "surfaceMaterial"), "Stone")
        XCTAssertEqual(row.parameter(named: "future"), "keep")
        XCTAssertNil(row.parameter(named: "name"))
        XCTAssertNil(row.parameter(named: "missing"))
        XCTAssertEqual(source.encoded(), before)
        XCTAssertTrue(try Dust3DDocument(data: Dust3DDocument.emptyArchive()).animations().isEmpty)
    }

    func testCommandsPreserveOpaqueMetadataAndExactUndoRedo() throws {
        let source = try document()
        var history = DocumentHistory(document: source)
        try history.beginTransaction()
        try history.apply(.setAnimationName(id: "a", name: "Rest <one>"))
        try history.apply(.setAnimationType(id: "a", type: "other-future-type"))
        try history.apply(.setAnimationParameter(id: "a", name: "duration", value: "2.50"))
        try history.apply(.setAnimationParameter(id: "a", name: "futureNew", value: "a&b"))
        try history.endTransaction()
        let edited = history.document.encoded()
        let row = try XCTUnwrap(history.document.animations().first)
        XCTAssertEqual(row.name, "Rest <one>")
        XCTAssertEqual(row.type, "other-future-type")
        XCTAssertEqual(row.parameter(named: "duration"), "2.50")
        XCTAssertEqual(row.parameter(named: "futureNew"), "a&b")
        XCTAssertEqual(row.parameter(named: "future"), "keep")
        let xml = String(decoding: history.document.modelXML, as: UTF8.self)
        XCTAssertTrue(xml.contains("opaqueRoot"))
        let parsed = try XMLDocument(data: history.document.modelXML)
        XCTAssertEqual(
            parsed.rootElement()?.elements(forName: "animations").first?
                .elements(forName: "animation").first?.elements(forName: "opaque").first?
                .attribute(forName: "value")?.stringValue, "retain")
        XCTAssertTrue(xml.contains("retain comment"))
        XCTAssertTrue(history.isDirty)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertFalse(history.isDirty)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited)
        XCTAssertEqual(try Dust3DDocument(data: edited).animations(), try history.document.animations())
    }

    func testCreateDuplicateAndDeletePreserveOrderNestedDataAndContainerMetadata() throws {
        var document = try document()
        document = try document.applying(.createAnimation(id: "b", name: "Walk", type: "walk"))
        document = try document.applying(.duplicateAnimation(id: "a", newID: "copy", name: "Idle copy"))
        XCTAssertEqual(try document.animations().map(\.id), ["a", "copy", "b"])
        let copy = try XCTUnwrap(document.animations().first { $0.id == "copy" })
        XCTAssertEqual(copy.type, "future-type")
        XCTAssertEqual(copy.parameter(named: "duration"), "1.00")
        XCTAssertEqual(copy.parameter(named: "future"), "keep")
        document = try document.applying(.deleteAnimation(id: "a"))
        let xml = String(decoding: document.modelXML, as: UTF8.self)
        let parsed = try XMLDocument(data: document.modelXML)
        XCTAssertEqual(
            parsed.rootElement()?.elements(forName: "animations").first?
                .elements(forName: "animation").first?.elements(forName: "opaque").first?
                .attribute(forName: "value")?.stringValue, "retain")
        XCTAssertTrue(xml.contains("retain comment"))
        document = try document.applying(.deleteAnimation(id: "copy"))
        document = try document.applying(.deleteAnimation(id: "b"))
        XCTAssertTrue(try document.animations().isEmpty)
        let empty = try XMLDocument(data: document.modelXML)
        XCTAssertEqual(
            empty.rootElement()?.elements(forName: "animations").first?
                .attribute(forName: "future")?.stringValue, "catalog")
    }

    func testRestoringExistingAnimationFieldsInOneTransactionRetainsExactBytesAndRedo() throws {
        let source = try document()
        var history = DocumentHistory(document: source)
        try history.apply(.setAnimationName(id: "a", name: "Redo name"))
        let redoBytes = history.document.encoded()
        XCTAssertTrue(history.undo())
        try history.beginTransaction()
        try history.apply(.setAnimationType(id: "a", type: "temporary-type"))
        try history.apply(.setAnimationParameter(id: "a", name: "duration", value: "9.25"))
        try history.apply(.setAnimationName(id: "a", name: "Temporary name"))
        try history.apply(.setAnimationType(id: "a", type: "future-type"))
        try history.apply(.setAnimationParameter(id: "a", name: "duration", value: "1.00"))
        try history.apply(.setAnimationName(id: "a", name: "Idle & rest"))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertFalse(history.isDirty)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), redoBytes)
    }

    func testNoOpsAndInvalidCommandsPreserveBytesAndRedo() throws {
        let source = try document()
        var history = DocumentHistory(document: source)
        try history.apply(.setAnimationName(id: "a", name: "changed"))
        XCTAssertTrue(history.undo())
        for command: DocumentCommand in [
            .setAnimationName(id: "a", name: "Idle & rest"),
            .setAnimationType(id: "a", type: "future-type"),
            .setAnimationParameter(id: "a", name: "duration", value: "1.00"),
            .setAnimationParameter(id: "a", name: "absent", value: nil),
        ] {
            try history.apply(command)
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
            XCTAssertFalse(history.canUndo)
        }
        let invalid: [DocumentCommand] = [
            .createAnimation(id: "a", name: "Duplicate", type: "walk"),
            .duplicateAnimation(id: "a", newID: "a", name: "copy"),
            .setAnimationName(id: "missing", name: "missing"),
            .deleteAnimation(id: "missing"),
            .createAnimation(id: "", name: "new", type: "walk"),
            .setAnimationName(id: "a", name: "bad\nname"),
            .setAnimationType(id: "a", type: ""),
            .setAnimationParameter(id: "a", name: "id", value: "retarget"),
            .setAnimationParameter(id: "a", name: "bad key", value: "value"),
            .setAnimationParameter(id: "a", name: "duration", value: String(repeating: "x", count: 4097)),
            .setAnimationParameter(id: "a", name: "xmlns", value: "urn:future"),
        ]
        for command in invalid {
            XCTAssertThrowsError(try history.apply(command)) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
        }
    }

    func testExactUtf8IdentitiesAndIncompleteRecordsRemainDistinct() throws {
        let first = "caf\u{e9}"
        let second = "cafe\u{301}"
        var source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='\(first)'/><animation id='\(second)' name='second' type='future'/></animations></canvas>"
                    .utf8))
        let rows = try source.animations()
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows[0] == rows[1])
        XCTAssertNil(rows[0].name)
        XCTAssertNil(rows[0].type)
        source = try source.applying(.setAnimationName(id: second, name: "changed"))
        XCTAssertNil(try source.animations()[0].name)
        XCTAssertEqual(try source.animations()[1].name, "changed")
        source = try source.applying(.setAnimationParameter(id: second, name: "future", value: "1"))
        source = try source.applying(.setAnimationParameter(id: second, name: "future", value: nil))
        XCTAssertNil(try source.animations()[1].parameter(named: "future"))
    }

    func testDuplicatePreservesNamespaceAndAllOpaqueAssetBytes() throws {
        let model = Data(
            "<canvas xmlns:x='urn:future'><animations><animation id='a' name='A' type='future' asset='retained.bin'><x:opaque value='retain'/></animation></animations></canvas>"
                .utf8)
        let asset = Data([0, 255, 1, 128])
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='retained.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let source = try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + asset)
        let duplicate = try source.applying(.duplicateAnimation(id: "a", newID: "b", name: "B"))
        let xml = String(decoding: duplicate.modelXML, as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<x:opaque").count - 1, 2)
        XCTAssertTrue(xml.contains("xmlns:x=\"urn:future\""))
        XCTAssertEqual(duplicate.asset(named: "retained.bin"), asset)
        let deleted = try duplicate.applying(.deleteAnimation(id: "a")).applying(.deleteAnimation(id: "b"))
        XCTAssertEqual(deleted.asset(named: "retained.bin"), asset)
        XCTAssertEqual(try Dust3DDocument(data: deleted.encoded()).asset(named: "retained.bin"), asset)
        XCTAssertEqual(source.modelXML, model)
    }

    func testCreateDeleteTransactionReturnsToExactCleanArchive() throws {
        let original = Dust3DDocument.emptyArchive()
        var history = DocumentHistory(document: try Dust3DDocument(data: original))
        try history.beginTransaction()
        try history.apply(.createAnimation(id: "fresh", name: "New", type: "future"))
        try history.apply(.deleteAnimation(id: "fresh"))
        try history.endTransaction()
        XCTAssertEqual(history.document.encoded(), original)
        XCTAssertFalse(history.isDirty)
        XCTAssertFalse(history.canUndo)
        let commented = try Dust3DDocument(
            snapshotXML: Data("<canvas><animations><!--keep--><animation id='a'/></animations></canvas>".utf8))
        let deleted = try commented.applying(.deleteAnimation(id: "a"))
        XCTAssertTrue(String(decoding: deleted.modelXML, as: UTF8.self).contains("<!--keep-->"))
    }

    func testExistingEmptyAnimationContainersReturnToExactCleanArchive() throws {
        for container in [
            "<animations/>", "<animations> </animations>", "<animations future='keep'><!--retain--></animations>",
            "<animations xmlns:x='urn:future'/>",
        ] {
            let source = try Dust3DDocument(snapshotXML: Data(("<canvas>" + container + "</canvas>").utf8))
            var history = DocumentHistory(document: source)
            try history.beginTransaction()
            try history.apply(.createAnimation(id: "fresh", name: "New", type: "future"))
            try history.apply(.deleteAnimation(id: "fresh"))
            try history.endTransaction()
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertFalse(history.isDirty)
            XCTAssertFalse(history.canUndo)
        }
    }

    func testCanonicalUnicodeEqualityCannotSuppressExactStoredTextChanges() throws {
        let first = "caf\u{e9}"
        let second = "cafe\u{301}"
        let original = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='\(first)' type='future' \(first)='one' \(second)='two'/></animations></canvas>"
                    .utf8))
        let row = try XCTUnwrap(original.animations().first)
        XCTAssertEqual(row.parameter(named: first), "one")
        XCTAssertEqual(row.parameter(named: second), "two")
        let renamed = try original.applying(.setAnimationName(id: "a", name: second))
        XCTAssertNotEqual(renamed.encoded(), original.encoded())
        XCTAssertNotEqual(try renamed.animations().first, row)
        let sameParameters = row.parameters
        XCTAssertNotEqual(
            DocumentAnimationParameter(name: first, value: "v"), DocumentAnimationParameter(name: second, value: "v"))
        XCTAssertNotEqual(
            DocumentAnimationParameter(name: "key", value: first),
            DocumentAnimationParameter(name: "key", value: second))
        XCTAssertEqual(row.parameters, sameParameters)
    }

    func testEditLimitsCountUtf8BytesAndKeepRejectedCommandsAtomic() throws {
        let id = String(repeating: "i", count: 1024)
        let name = String(repeating: "😀", count: 256)
        let type = String(repeating: "t", count: 1024)
        let key = "p" + String(repeating: "1", count: 127)
        let value = String(repeating: "é", count: 2048)
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
            .applying(.createAnimation(id: id, name: name, type: type))
            .applying(.setAnimationParameter(id: id, name: key, value: value))
        let before = source.encoded()
        let row = try XCTUnwrap(source.animations().first)
        XCTAssertEqual(row.id.utf8.count, 1024)
        XCTAssertEqual(row.name?.utf8.count, 1024)
        XCTAssertEqual(row.type?.utf8.count, 1024)
        XCTAssertEqual(row.parameter(named: key)?.utf8.count, 4096)
        for command: DocumentCommand in [
            .createAnimation(id: id + "x", name: "new", type: "future"),
            .setAnimationName(id: id, name: name + "x"),
            .setAnimationType(id: id, type: type + "x"),
            .setAnimationParameter(id: id, name: key + "x", value: "value"),
            .setAnimationParameter(id: id, name: key, value: value + "x"),
            .setAnimationParameter(id: id, name: "name", value: "retarget"),
            .setAnimationParameter(id: id, name: "type", value: "retarget"),
            .setAnimationParameter(id: id, name: "x:future", value: "value"),
            .setAnimationParameter(id: id, name: "9future", value: "value"),
            .setAnimationName(id: id, name: "\u{fffe}"),
        ] {
            XCTAssertThrowsError(try source.applying(command))
            XCTAssertEqual(source.encoded(), before)
        }
        let clearedName = try source.applying(.setAnimationName(id: id, name: ""))
        XCTAssertEqual(try clearedName.animations().first?.name, "")
        let punctuation = try clearedName.applying(.setAnimationParameter(id: id, name: "_future.value-1", value: ""))
        XCTAssertEqual(try punctuation.animations().first?.parameter(named: "_future.value-1"), "")
    }

    func testAppendAdmissionCountsOpaqueElementsWithSmallUnitLimit() throws {
        let xml = try XMLDocument(xmlString: "<canvas><animations><animation id='a'/><future/></animations></canvas>")
        let root = try XCTUnwrap(xml.rootElement())
        let before = xml.xmlData(options: [.nodePreserveAll])
        XCTAssertThrowsError(try AnimationMetadata.admitAppend(root, maximumCount: 2)) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        XCTAssertEqual(try AnimationMetadata.admitAppend(root, maximumCount: 3).count, 1)
        XCTAssertEqual(xml.xmlData(options: [.nodePreserveAll]), before)
    }

    func testAmbiguousMetadataAndSmallCallerLimitsRejectWithoutMutation() throws {
        for xml in [
            "<canvas><animations/><animations/></canvas>",
            "<canvas><animations><animation id='a'/><animation id='a'/></animations></canvas>",
            "<canvas><animations><animation/></animations></canvas>",
            "<canvas><animations><future id='a'/></animations></canvas>",
        ] {
            let source = try Dust3DDocument(snapshotXML: Data(xml.utf8))
            let before = source.encoded()
            XCTAssertThrowsError(try source.animations()) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            XCTAssertEqual(source.encoded(), before)
        }
        let source = try document().applying(.createAnimation(id: "b", name: "Walk", type: "walk"))
        XCTAssertThrowsError(try source.animations(maximumCount: 1)) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        XCTAssertThrowsError(try source.animations(maximumCount: -1))
        XCTAssertThrowsError(try source.animations(maximumCount: 10_001))
    }
}
