import Dust3DDocument
import Foundation
import XCTest

final class ComponentSurfaceDetailsTests: XCTestCase {
    private func document(_ attributes: String = "") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas future='retained'><nodes/><edges/><parts/><components><component id='g' wrap='Cloth' future='opaque' \(attributes)><!--keep--><component id='child'/></component></components></canvas>"
                    .utf8))
    }
    private func details(_ document: Dust3DDocument) throws -> ComponentSurfaceDetails {
        try XCTUnwrap(document.components().first).wrapping.surfaceDetails
    }

    func testDefaultsAndUnknownSourceValuesRemainLossless() throws {
        let source = try document()
        let settings = try details(source)
        XCTAssertEqual(settings.pattern, ComponentSurfacePattern.none)
        XCTAssertEqual(settings.ink, .unset)
        for property in ComponentSurfaceScalar.allCases {
            XCTAssertEqual(settings.scalarValue(property), property.defaultValue)
        }
        let opaque = try document(
            "wrapPattern='future' wrapPatternColor='future' wrapPatternScale='future' wrapBelly='nan' wrapWrinkles='2' wrapWrinkleSize='0'"
        )
        XCTAssertNil(try details(opaque).pattern)
        XCTAssertEqual(try details(opaque).ink, .unsupported("future"))
        for property in ComponentSurfaceScalar.allCases { XCTAssertNil(try details(opaque).scalarValue(property)) }
        XCTAssertEqual(try Dust3DDocument(data: opaque.encoded()).encoded(), opaque.encoded())
    }

    func testAllPatternsAndScalarEditsPreserveOpaqueFieldsWithExactUndoRedoAndReopen() throws {
        let source = try document("wrapBindTo='opaque-body' wrapFuture='retain'")
        for pattern in ComponentSurfacePattern.allCases {
            let changed = try source.applying(.setComponentSurfacePattern(id: "g", pattern: pattern))
            XCTAssertEqual(try details(changed).pattern, pattern)
            XCTAssertTrue(String(decoding: changed.modelXML, as: UTF8.self).contains("opaque-body"))
        }
        for property in ComponentSurfaceScalar.allCases {
            var history = DocumentHistory(document: source)
            let before = history.previewIdentity
            try history.apply(
                .setComponentSurfaceScalar(id: "g", property: property, value: property.bounds.upperBound))
            let changed = history.document
            XCTAssertEqual(try details(changed).scalarValue(property), property.bounds.upperBound)
            XCTAssertEqual(history.previewIdentity.geometry, before.geometry)
            XCTAssertNotEqual(history.previewIdentity.materials, before.materials)
            XCTAssertEqual(try details(Dust3DDocument(data: changed.encoded())), try details(changed))
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertFalse(history.canUndo)
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
            XCTAssertTrue(String(decoding: changed.modelXML, as: UTF8.self).contains("wrapFuture"))
        }
    }

    func testDefaultAndAutomaticRemovalAreFieldLocalAndSemanticNoOpsKeepBytes() throws {
        let source = try document(
            "wrapPattern='Spots' wrapPatternColor='#aB01fF' wrapWrinkles='0.7' wrapWrinkleSize='2'")
        let same = try source.applying(.setComponentSurfaceColor(id: "g", color: .init(red: 171, green: 1, blue: 255)))
        XCTAssertEqual(same.encoded(), source.encoded())
        let auto = try source.applying(.setComponentSurfaceColor(id: "g", color: nil))
        XCTAssertEqual(try details(auto).ink, .unset)
        let cleared = try auto.applying(.setComponentSurfacePattern(id: "g", pattern: .none))
        XCTAssertEqual(try details(cleared).scalarValue(.wrinkles), 0.7)
        let reset = try cleared.applying(.setComponentSurfaceScalar(id: "g", property: .wrinkleSize, value: 1))
        XCTAssertFalse(String(decoding: reset.modelXML, as: UTF8.self).contains("wrapWrinkleSize="))
        let disabled = try source.applying(.setComponentWrapMode(id: "g", mode: .none))
        XCTAssertEqual(try details(disabled), try details(source))
        let defaults = try document("wrapPatternScale='.0600'")
        XCTAssertEqual(
            try defaults.applying(.setComponentSurfaceScalar(id: "g", property: .patternScale, value: 0.06)).encoded(),
            defaults.encoded())
    }

    func testInvalidInputsAndNonGroupsRejectAtomically() throws {
        let source = try document()
        for property in ComponentSurfaceScalar.allCases {
            for value in [Double.nan, .infinity, -1, property.bounds.upperBound + 1] {
                XCTAssertThrowsError(
                    try source.applying(.setComponentSurfaceScalar(id: "g", property: property, value: value)))
            }
            XCTAssertThrowsError(
                try source.applying(
                    .setComponentSurfaceScalar(id: "missing", property: property, value: property.defaultValue)))
        }
        XCTAssertThrowsError(
            try source.applying(.setComponentSurfaceColor(id: "g", color: .init(red: 1, green: 2, blue: 3, alpha: 100)))
        )
        let linked = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                    .utf8))
        XCTAssertThrowsError(try linked.applying(.setComponentSurfacePattern(id: "c", pattern: .spots)))
        XCTAssertThrowsError(try linked.applying(.setComponentSurfaceColor(id: "c", color: nil)))
        XCTAssertThrowsError(try source.applying(.setComponentSurfaceColor(id: "missing", color: nil)))
        XCTAssertThrowsError(try source.applying(.setComponentSurfacePattern(id: "missing", pattern: .spots)))
    }
    func testUnsupportedFieldReplacementIsLocalAndDefaultAutomaticNoOpsKeepExactBytes() throws {
        let opaque = try document(
            "wrapPattern='future' wrapPatternColor='future' wrapPatternScale='future' wrapBelly='future' wrapWrinkles='future' wrapWrinkleSize='future' wrapBindTo='opaque-body'"
        )
        let pattern = try opaque.applying(.setComponentSurfacePattern(id: "g", pattern: .mottled))
        XCTAssertEqual(try details(pattern).pattern, .mottled)
        XCTAssertEqual(try details(pattern).ink, .unsupported("future"))
        XCTAssertNil(try details(pattern).scalarValue(.wrinkles))
        let ink = try opaque.applying(.setComponentSurfaceColor(id: "g", color: nil))
        XCTAssertEqual(try details(ink).ink, .unset)
        XCTAssertNil(try details(ink).pattern)
        for property in ComponentSurfaceScalar.allCases {
            let replaced = try opaque.applying(
                .setComponentSurfaceScalar(id: "g", property: property, value: property.defaultValue))
            XCTAssertEqual(try details(replaced).scalarValue(property), property.defaultValue)
            XCTAssertNil(try details(replaced).pattern)
            XCTAssertEqual(try details(replaced).ink, .unsupported("future"))
            XCTAssertTrue(String(decoding: replaced.modelXML, as: UTF8.self).contains("opaque-body"))
        }
        let defaults = try document("wrapPattern='' wrapPatternColor='' wrapWrinkles='0.000'")
        XCTAssertEqual(
            try defaults.applying(.setComponentSurfaceColor(id: "g", color: nil)).encoded(), defaults.encoded())
        XCTAssertEqual(
            try defaults.applying(.setComponentSurfacePattern(id: "g", pattern: .none)).encoded(), defaults.encoded())
        XCTAssertEqual(try details(document("wrapPatternColor='#80112233'")).ink, .unsupported("#80112233"))
        var limited = DocumentHistory(document: opaque, maximumUndoBytes: 1)
        XCTAssertThrowsError(try limited.apply(.setComponentSurfacePattern(id: "g", pattern: .spots)))
        XCTAssertEqual(limited.document.encoded(), opaque.encoded())
    }

    func testSurfaceCommandsRequireLiteralComponentIDs() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='cafe&#769;' wrap='Cloth'/></components></canvas>"
                    .utf8))
        let alias = "caf\u{e9}"
        let actual = "cafe\u{301}"
        let commands: [DocumentCommand] = [
            .setComponentSurfacePattern(id: alias, pattern: .spots),
            .setComponentSurfaceScalar(id: alias, property: .wrinkles, value: 0.5),
            .setComponentSurfaceColor(id: alias, color: .init(red: 1, green: 2, blue: 3)),
        ]
        for command in commands {
            var history = DocumentHistory(document: source)
            XCTAssertThrowsError(try history.apply(command))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertFalse(history.canUndo)
        }
        var history = DocumentHistory(document: source)
        try history.apply(.setComponentSurfacePattern(id: actual, pattern: .spots))
        XCTAssertEqual(try details(history.document).pattern, .spots)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
    }

}
