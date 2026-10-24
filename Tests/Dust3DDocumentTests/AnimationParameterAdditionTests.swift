import Foundation
import XCTest

@testable import Dust3DDocument

final class AnimationParameterAdditionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas xmlns:ext='urn:keep'><animations><animation id='a' type='future' gain='' ext:gain='opaque'><ext:child/></animation></animations></canvas>"
                    .utf8))
    }
    func testAddingParameterRejectsExistingEmptyAndNonemptyValuesWithoutChangingHistory() throws {
        let source = try document()
        var history = DocumentHistory(document: source)
        XCTAssertThrowsError(try history.apply(.addAnimationParameter(id: "a", name: "gain", value: "replace"))) {
            XCTAssertEqual($0 as? DocumentAnimationError, .parameterAlreadyExists("gain"))
        }
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertFalse(history.canUndo)
        try history.apply(.addAnimationParameter(id: "a", name: "Gain", value: "new"))
        let saved = history.document.encoded()
        XCTAssertThrowsError(try history.apply(.addAnimationParameter(id: "a", name: "Gain", value: "replace"))) {
            XCTAssertEqual($0 as? DocumentAnimationError, .parameterAlreadyExists("Gain"))
        }
        XCTAssertEqual(history.document.encoded(), saved)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), saved)
        let reopened = try Dust3DDocument(data: saved)
        let row = try XCTUnwrap(reopened.animations().first)
        XCTAssertEqual(row.parameter(named: "gain"), "")
        XCTAssertEqual(row.parameter(named: "Gain"), "new")
        XCTAssertEqual(row.parameter(named: "ext:gain"), "opaque")
        XCTAssertTrue(String(decoding: reopened.modelXML, as: UTF8.self).contains("ext:child"))
    }
    func testAdditionValidatesNamesValuesAndMissingRowsBeforePublication() throws {
        let source = try document()
        for (id, name, value, expected) in [
            ("a", "xmlns", "new", DocumentAnimationError.invalidParameter),
            ("a", "ext:new", "new", .invalidParameter),
            ("a", "new", "bad\nvalue", .invalidParameter),
            ("missing", "new", "", .missingAnimation("missing")),
        ] {
            XCTAssertThrowsError(try source.applying(.addAnimationParameter(id: id, name: name, value: value))) {
                XCTAssertEqual($0 as? DocumentAnimationError, expected)
            }
        }
        let result = try source.applying(.addAnimationParameter(id: "a", name: "empty", value: ""))
        XCTAssertEqual(try result.animations().first?.parameter(named: "empty"), "")
        XCTAssertEqual(try source.animations().first?.parameter(named: "empty"), nil)
    }
}
