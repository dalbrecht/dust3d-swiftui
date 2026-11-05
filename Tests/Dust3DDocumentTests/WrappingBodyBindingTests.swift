import Dust3DDocument
import Foundation
import XCTest

final class WrappingBodyBindingTests: XCTestCase {
    private func source(_ binding: String? = "missing") throws -> Dust3DDocument {
        let attribute = binding.map { "wrapBindTo='\($0)'" } ?? ""
        return try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts><part id='p' locked='true'/></parts><components><component id='ancestor' name='Ancestor'><component id='owner' wrap='Cloth' \(attribute) future='keep' wrapPattern='Future'><!--keep--><component id='child'/><component id='leaf' linkDataType='partId' linkData='p'/></component></component><component id='body' name='Body'/><component id='linked' linkDataType='partId' linkData='p'/><component id='opaque' linkDataType='future' linkData='body'/></components></canvas>
                """.utf8))
    }
    private func value(_ document: Dust3DDocument) throws -> ComponentWrapBindingValue {
        try XCTUnwrap(document.components().first { $0.id == "owner" }).wrapping.binding
    }
    func testLosslessSourceValuesAndQtCandidatesAllowAncestorsWithoutInterpretingBindingCycles() throws {
        for text in ["missing", "owner", " child ", "", "caf\u{e9}", "cafe\u{301}"] {
            let document = try source(text)
            XCTAssertEqual(try value(document), .stored(text))
            XCTAssertEqual(try Dust3DDocument(data: document.encoded()).encoded(), document.encoded())
        }
        XCTAssertEqual(try value(source(nil)), .absent)
        XCTAssertNotEqual(ComponentWrapBindingValue.stored("caf\u{e9}"), .stored("cafe\u{301}"))
        let document = try source("ancestor")
        let plan = try ComponentWrapBindingPlan(components: document.components(), ownerIDs: ["owner"])
        XCTAssertEqual(Set(plan.candidates.map(\.id)), ["ancestor", "body"])
        // The ancestor is eligible even though it contains the owner; the binding does not recurse through wraps.
        let changed = try document.applying(.setComponentWrapBinding(id: "owner", choice: .group("ancestor")))
        XCTAssertEqual(changed.encoded(), document.encoded())
    }
    func testPickerChoicesKeepByteDistinctReferencesAsDifferentDictionaryKeys() {
        let first = ComponentWrapBindingChoice.group("caf\u{e9}")
        let second = ComponentWrapBindingChoice.group("cafe\u{301}")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second, .ownChildren]).count, 3)
        var values: [ComponentWrapBindingChoice: String] = [:]
        values[first] = "first"
        values[second] = "second"
        XCTAssertEqual(values.count, 2)
    }
    func testFieldLocalReplacementAdvancesGeometryAndMaterialsWithExactHistoryAndOpaquePreservation() throws {
        let original = try source()
        var history = DocumentHistory(document: original)
        let before = history.previewIdentity
        try history.apply(.setComponentWrapBinding(id: "owner", choice: .group("body")))
        let changed = history.document
        XCTAssertEqual(try value(changed), .stored("body"))
        XCTAssertNotEqual(history.previewIdentity.geometry, before.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, before.materials)
        let xml = String(decoding: changed.modelXML, as: UTF8.self)
        XCTAssertTrue(xml.contains("keep"))
        XCTAssertTrue(xml.contains("Future"))
        XCTAssertEqual(try changed.editorContents().parts, try original.editorContents().parts)
        XCTAssertEqual(try value(Dust3DDocument(data: changed.encoded())), .stored("body"))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
        try history.apply(.setComponentWrapBinding(id: "owner", choice: .ownChildren))
        XCTAssertEqual(try value(history.document), .absent)
    }
    func testNoopsKeepExactSourceSpellingRedoAndPreviewWhileInvalidAuthoredTargetsRejectAtomically() throws {
        for (raw, choice): (String?, ComponentWrapBindingChoice) in [
            ("body", .group("body")), ("", .ownChildren), (nil, .ownChildren),
        ] {
            let original = try source(raw)
            var history = DocumentHistory(document: original)
            try history.apply(.setComponentName(id: "owner", name: "Temporary"))
            XCTAssertTrue(history.undo())
            let identity = history.previewIdentity
            try history.apply(.setComponentWrapBinding(id: "owner", choice: choice))
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertEqual(history.previewIdentity, identity)
            XCTAssertTrue(history.canRedo)
        }
        let original = try source("owner")
        for target in ["owner", "child", "leaf", "linked", "opaque", "missing"] {
            var history = DocumentHistory(document: original)
            XCTAssertThrowsError(try history.apply(.setComponentWrapBinding(id: "owner", choice: .group(target)))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentWrapBinding)
            }
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertFalse(history.canUndo)
        }
        XCTAssertThrowsError(try original.applying(.setComponentWrapBinding(id: "linked", choice: .ownChildren)))
    }
}
