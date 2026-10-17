import Dust3DDocument
import Foundation
import XCTest

final class ComponentStitchingTests: XCTestCase {
    private func document(_ attributes: String = "") throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='canvas'><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' locked='true'/></parts><components><component id='g' future='keep' \(attributes)><!--keep--><future value='opaque'/><component id='c' linkDataType='partId' linkData='p'/></component></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    private func settings(_ document: Dust3DDocument) throws -> ComponentStitchingSettings {
        try XCTUnwrap(document.components().first(where: { $0.id == "g" })).stitching
    }

    func testDefaultsAndKnownOrUnsupportedSourceValuesNeverRewriteArchive() throws {
        let source = try document()
        let defaults = try settings(source)
        XCTAssertEqual(defaults.targetSegments, 0)
        for property in ComponentStitchingClosureProperty.allCases {
            XCTAssertEqual(defaults.closureValue(property), false)
            for text in ["true", "True", "1", "false", "False", "0", "", "future"] {
                let original = try document("\(property.rawValue)='\(text)'")
                let expected: Bool? = ["true", "True", "1"].contains(text) ? true : text == "future" ? nil : false
                XCTAssertEqual(try settings(original).closureValue(property), expected)
                XCTAssertEqual(try Dust3DDocument(data: original.encoded()).encoded(), original.encoded())
            }
        }
        for property in ComponentStitchingScalarProperty.allCases {
            XCTAssertEqual(defaults.scalarValue(property), property.defaultValue)
            for text in ["0", "0.005", "0,005", "1", "", "future", "nan", "inf", "-0.1", "2.1", "1e-50", "1e-999"] {
                let original = try document("\(property.rawValue)='\(text)'")
                let expected =
                    ["0", "0.005", "0,005", "1"].contains(text)
                    ? Double(text.replacingOccurrences(of: ",", with: ".")) : nil
                XCTAssertEqual(try settings(original).scalarValue(property), expected)
                XCTAssertEqual(try Dust3DDocument(data: original.encoded()).encoded(), original.encoded())
            }
        }
        for text in ["0", "001", "+10", "100", "", "future", "1.5", "1e1", "-1", "101"] {
            XCTAssertEqual(
                try settings(document("targetSegments='\(text)'")).targetSegments,
                ["0", "001", "+10", "100"].contains(text) ? Int(text) : nil)
        }
    }

    func testEachSettingPreservesGraphHierarchyOpaqueContentAssetsAndExactHistory() throws {
        var commands = ComponentStitchingClosureProperty.allCases.map {
            DocumentCommand.setComponentStitchingClosure(id: "g", property: $0, value: true)
        }
        commands += ComponentStitchingScalarProperty.allCases.map {
            .setComponentStitchingScalar(id: "g", property: $0, value: 0.005)
        }
        commands += [.setComponentTargetSegments(id: "g", segments: 100)]
        for command in commands {
            let source = try document()
            var history = DocumentHistory(document: source)
            try history.apply(command)
            let changed = history.document
            XCTAssertNotEqual(changed.encoded(), source.encoded())
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            XCTAssertEqual(try changed.editorContents().parts, try source.editorContents().parts)
            XCTAssertEqual(try changed.components().map(\.id), ["g", "c"])
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            let xml = try XMLDocument(data: changed.modelXML)
            let group = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='g']").first as? XMLElement)
            XCTAssertEqual(group.attribute(forName: "future")?.stringValue, "keep")
            XCTAssertTrue(group.xmlString.contains("<!--keep-->"))
            XCTAssertEqual(group.elements(forName: "future").first?.attribute(forName: "value")?.stringValue, "opaque")
            XCTAssertEqual(try settings(Dust3DDocument(data: changed.encoded())), try settings(changed))
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }

    func testSemanticNoOpsKeepSourceSpellingsAndRedoAndDefaultsRemoveOnlyChangedAttributes() throws {
        let source = try document(
            "frontClosed='1' backClosed='False' sideClosed='' targetSegments='001' backCloseDepthRatio='1,0' backCloseSharpness='0.000'"
        )
        var history = DocumentHistory(document: source)
        try history.apply(.setComponentName(id: "g", name: "Temporary"))
        XCTAssertTrue(history.undo())
        for property in ComponentStitchingClosureProperty.allCases {
            try history.apply(
                .setComponentStitchingClosure(
                    id: "g", property: property,
                    value: try XCTUnwrap(settings(source).closureValue(property))))
        }
        for property in ComponentStitchingScalarProperty.allCases {
            try history.apply(
                .setComponentStitchingScalar(
                    id: "g", property: property,
                    value: try XCTUnwrap(settings(source).scalarValue(property))))
        }
        try history.apply(.setComponentTargetSegments(id: "g", segments: 1))
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertTrue(history.canRedo)
        let resets: [(DocumentCommand, String)] = [
            (.setComponentStitchingClosure(id: "g", property: .front, value: false), "frontClosed"),
            (.setComponentTargetSegments(id: "g", segments: 0), "targetSegments"),
        ]
        for (command, attribute) in resets {
            let changed = try source.applying(command)
            let xml = try XMLDocument(data: changed.modelXML)
            let group = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='g']").first as? XMLElement)
            XCTAssertNil(group.attribute(forName: attribute))
        }
        for property in ComponentStitchingScalarProperty.allCases {
            let changed = try document("\(property.rawValue)='0.005'").applying(
                .setComponentStitchingScalar(id: "g", property: property, value: property.defaultValue))
            let xml = try XMLDocument(data: changed.modelXML)
            let group = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='g']").first as? XMLElement)
            XCTAssertNil(group.attribute(forName: property.rawValue))
        }
    }

    func testInvalidValuesAndMissingOwnersRejectWithoutChangingArchiveOrRedo() throws {
        let source = try document()
        var history = DocumentHistory(document: source)
        try history.apply(.setComponentName(id: "g", name: "Temporary"))
        XCTAssertTrue(history.undo())
        for value in [-1, 101, Int.max, Int.min] {
            XCTAssertThrowsError(try history.apply(.setComponentTargetSegments(id: "g", segments: value))) {
                XCTAssertEqual($0 as? DocumentError, .invalidComponentTargetSegments)
            }
        }
        for property in ComponentStitchingScalarProperty.allCases {
            for value in [
                -0.1, property.bounds.upperBound + 0.1, Double.nan, .infinity, 1e-50, Double.leastNonzeroMagnitude,
            ] {
                XCTAssertThrowsError(
                    try history.apply(.setComponentStitchingScalar(id: "g", property: property, value: value))
                ) {
                    XCTAssertEqual($0 as? DocumentError, .invalidComponentStitchingScalar)
                }
            }
            for value in [property.bounds.lowerBound, property.bounds.upperBound, Double(Float.leastNonzeroMagnitude)] {
                XCTAssertEqual(
                    try settings(
                        source.applying(.setComponentStitchingScalar(id: "g", property: property, value: value))
                    ).scalarValue(property), value)
            }
        }
        for command in [
            DocumentCommand.setComponentTargetSegments(id: "missing", segments: 1),
            .setComponentStitchingClosure(id: "missing", property: .front, value: true),
            .setComponentStitchingScalar(id: "missing", property: .depthRatio, value: 1),
        ] {
            XCTAssertThrowsError(try history.apply(command)) {
                XCTAssertEqual($0 as? DocumentError, .missingComponent("missing"))
            }
        }
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertTrue(history.canRedo)
    }
}
