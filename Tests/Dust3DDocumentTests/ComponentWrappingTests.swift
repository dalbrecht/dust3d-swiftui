import Dust3DDocument
import Foundation
import XCTest

final class ComponentWrappingTests: XCTestCase {
    private func document(_ attributes: String = "", opaqueGraph: Bool = false) throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='canvas'><nodes><node id='n' partId='\(opaqueGraph ? "missing" : "p")' x='.5' y='.5' z='.5' radius='.2'/></nodes><edges/><parts><part id='p' locked='true'/></parts><components><component id='g' future='keep' \(attributes)><!--keep--><future value='opaque'/><component id='c' linkDataType='partId' linkData='p'/></component></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    private func settings(_ document: Dust3DDocument) throws -> ComponentWrappingSettings {
        try XCTUnwrap(document.components().first(where: { $0.id == "g" })).wrapping
    }
    func testModeDependentDefaultsAndUnsupportedValuesNeverRewriteSource() throws {
        for mode in ComponentWrapMode.allCases {
            let source = try document("wrap='\(mode.rawValue)'")
            let wrapping = try settings(source)
            XCTAssertEqual(wrapping.mode, mode)
            XCTAssertEqual(wrapping.keepsChildren, mode == .cloth)
            XCTAssertEqual(wrapping.targetFaces, mode == .cloth ? 1200 : 1600)
            for property in ComponentWrappingScalarProperty.allCases {
                XCTAssertEqual(wrapping.scalarValue(property), property.defaultValue(for: mode))
                for text in ["nan", "inf", "future", "1e-50", "1e-999", "-0.1", "1000000"] {
                    let unknown = try document("wrap='\(mode.rawValue)' \(property.rawValue)='\(text)'")
                    XCTAssertNil(try settings(unknown).scalarValue(property))
                    XCTAssertEqual(try Dust3DDocument(data: unknown.encoded()).encoded(), unknown.encoded())
                }
                // Empty optional wrap numbers use the inherited mode default.
                XCTAssertEqual(
                    try settings(document("wrap='\(mode.rawValue)' \(property.rawValue)='' ")).scalarValue(property),
                    property.defaultValue(for: mode))
            }
            XCTAssertEqual(try Dust3DDocument(data: source.encoded()).encoded(), source.encoded())
        }
        let unknown = try settings(document("wrap='Future'"))
        XCTAssertNil(unknown.mode)
        XCTAssertNil(unknown.keepsChildren)
        XCTAssertNil(unknown.targetFaces)
        for property in ComponentWrappingScalarProperty.allCases { XCTAssertNil(unknown.scalarValue(property)) }
        for text in ["63", "20001", "40000", "64.5", "nan", "future"] {
            XCTAssertNil(try settings(document("wrapFaces='\(text)'")).targetFaces)
        }
        XCTAssertNil(try settings(document("wrapKeep='future'")).keepsChildren)
        for text in ["true", "True", "1"] {
            XCTAssertEqual(try settings(document("wrapKeep='\(text)'")).keepsChildren, true)
        }
        for text in ["false", "False", "0"] {
            XCTAssertEqual(try settings(document("wrapKeep='\(text)'")).keepsChildren, false)
        }
        XCTAssertEqual(try settings(document("wrapOffset='0,005'")).scalarValue(.offset), 0.005)
        XCTAssertEqual(try settings(document("wrapFaces='0064'")).targetFaces, 64)
    }
    func testCommandsPreserveOpaqueContentGraphAssetsAndExactHistory() throws {
        var commands: [DocumentCommand] = [
            .setComponentWrapMode(id: "g", mode: .cloth), .setComponentWrapKeepChildren(id: "g", value: true),
            .setComponentWrapFaces(id: "g", faces: 64),
        ]
        commands += ComponentWrappingScalarProperty.allCases.map {
            .setComponentWrapScalar(id: "g", property: $0, value: $0.bounds.upperBound)
        }
        for command in commands {
            let source = try document("wrap='Skin' wrapPattern='Future' wrapBindTo='unresolved'")
            var history = DocumentHistory(document: source)
            try history.apply(command)
            let changed = history.document
            XCTAssertNotEqual(changed.encoded(), source.encoded())
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            XCTAssertEqual(try changed.editorContents().parts, try source.editorContents().parts)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            let group = try XCTUnwrap(
                try XMLDocument(data: changed.modelXML).nodes(forXPath: "//component[@id='g']").first as? XMLElement)
            for (name, value) in [("future", "keep"), ("wrapPattern", "Future"), ("wrapBindTo", "unresolved")] {
                XCTAssertEqual(group.attribute(forName: name)?.stringValue, value)
            }
            XCTAssertTrue(group.xmlString.contains("<!--keep-->"))
            XCTAssertEqual(group.elements(forName: "future").count, 1)
            XCTAssertEqual(try changed.components().map(\.id), ["g", "c"])
            XCTAssertEqual(try settings(Dust3DDocument(data: changed.encoded())), try settings(changed))
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }
    func testNoOpsPreserveSpellingsRedoAndChangingModesRetainsParameters() throws {
        let source = try document(
            "wrap='Cloth' wrapKeep='True' wrapFaces='01200' wrapOffset='0,012' wrapThickness='0.0040'")
        var history = DocumentHistory(document: source)
        try history.apply(.setComponentName(id: "g", name: "Temporary"))
        XCTAssertTrue(history.undo())
        try history.apply(.setComponentWrapMode(id: "g", mode: .cloth))
        try history.apply(.setComponentWrapKeepChildren(id: "g", value: true))
        try history.apply(.setComponentWrapFaces(id: "g", faces: 1200))
        try history.apply(.setComponentWrapScalar(id: "g", property: .offset, value: 0.012))
        try history.apply(.setComponentWrapScalar(id: "g", property: .thickness, value: 0.004))
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertTrue(history.canRedo)
        let changed = try source.applying(.setComponentWrapMode(id: "g", mode: .skin))
        XCTAssertEqual(try settings(changed).scalarValue(.offset), 0.012)
        XCTAssertEqual(try settings(changed).keepsChildren, true)
        XCTAssertEqual(try settings(changed).targetFaces, 1200)
        let disabled = try changed.applying(.setComponentWrapMode(id: "g", mode: .none))
        XCTAssertEqual(try settings(disabled).scalarValue(.thickness), 0.004)
    }
    func testInvalidEditsAndLinkedOwnersRejectAtomicallyAndDefaultsRemoveOnlyChangedAttributes() throws {
        let source = try document("wrap='Cloth'")
        for property in ComponentWrappingScalarProperty.allCases {
            for value in [-1, property.bounds.upperBound + 1, Double.nan, .infinity, 1e-50] {
                XCTAssertThrowsError(
                    try source.applying(.setComponentWrapScalar(id: "g", property: property, value: value))
                ) { XCTAssertEqual($0 as? DocumentError, .invalidComponentWrapping) }
            }
            for value in [property.bounds.lowerBound, property.bounds.upperBound, Double(Float.leastNonzeroMagnitude)] {
                let edited = try source.applying(.setComponentWrapScalar(id: "g", property: property, value: value))
                XCTAssertEqual(try settings(edited).scalarValue(property), value)
            }
            let edited = try source.applying(
                .setComponentWrapScalar(id: "g", property: property, value: property.bounds.upperBound))
            let reset = try edited.applying(
                .setComponentWrapScalar(id: "g", property: property, value: property.defaultValue(for: .cloth)))
            let group = try XCTUnwrap(
                try XMLDocument(data: reset.modelXML).nodes(forXPath: "//component[@id='g']").first as? XMLElement)
            XCTAssertNil(group.attribute(forName: property.rawValue))
        }
        for faces in [63, 20001, Int.min, Int.max] {
            XCTAssertThrowsError(try source.applying(.setComponentWrapFaces(id: "g", faces: faces)))
        }
        for id in ["c", "missing"] {
            for command in [
                DocumentCommand.setComponentWrapMode(id: id, mode: .skin),
                .setComponentWrapKeepChildren(id: id, value: false), .setComponentWrapFaces(id: id, faces: 64),
                .setComponentWrapScalar(id: id, property: .offset, value: 0.01),
            ] {
                var history = DocumentHistory(document: source)
                try history.apply(.setComponentName(id: "g", name: "Temporary"))
                XCTAssertTrue(history.undo())
                XCTAssertThrowsError(try history.apply(command)) {
                    XCTAssertEqual(
                        $0 as? DocumentError, id == "missing" ? .missingComponent(id) : .invalidComponentWrapping)
                }
                XCTAssertEqual(history.document.encoded(), source.encoded())
                XCTAssertTrue(history.canRedo)
            }
        }
    }
    func testUnknownDefaultsCanBeReplacedExplicitlyAndChangedDefaultsRemoveAttributes() throws {
        let unknown = try document("wrap='Future' wrapKeep='future' wrapFaces='40000' wrapOffset='future'")
        var changed = try unknown.applying(.setComponentWrapKeepChildren(id: "g", value: false))
        changed = try changed.applying(.setComponentWrapFaces(id: "g", faces: 1600))
        changed = try changed.applying(.setComponentWrapScalar(id: "g", property: .offset, value: 0))
        XCTAssertNil(try settings(changed).mode)
        XCTAssertEqual(try settings(changed).keepsChildren, false)
        XCTAssertEqual(try settings(changed).targetFaces, 1600)
        XCTAssertEqual(try settings(changed).scalarValue(.offset), 0)
        changed = try changed.applying(.setComponentWrapMode(id: "g", mode: .cloth))
        changed = try changed.applying(.setComponentWrapKeepChildren(id: "g", value: true))
        changed = try changed.applying(.setComponentWrapFaces(id: "g", faces: 1200))
        let group = try XCTUnwrap(
            try XMLDocument(data: changed.modelXML).nodes(forXPath: "//component[@id='g']").first as? XMLElement)
        XCTAssertNil(group.attribute(forName: "wrapKeep"))
        XCTAssertNil(group.attribute(forName: "wrapFaces"))
        XCTAssertEqual(group.attribute(forName: "wrapOffset")?.stringValue, "0.0")
        let source = try document()
        XCTAssertEqual(try source.applying(.setComponentWrapMode(id: "g", mode: .none)).encoded(), source.encoded())
        XCTAssertEqual(
            try source.applying(.setComponentWrapKeepChildren(id: "g", value: false)).encoded(), source.encoded())
        XCTAssertEqual(try source.applying(.setComponentWrapFaces(id: "g", faces: 1600)).encoded(), source.encoded())
    }

    func testWrappingCommandsDoNotDecodeOrRewriteOpaqueGraphData() throws {
        let source = try document(opaqueGraph: true)
        XCTAssertThrowsError(try source.editorContents())
        for command in [
            DocumentCommand.setComponentWrapMode(id: "g", mode: .cloth),
            .setComponentWrapKeepChildren(id: "g", value: true), .setComponentWrapFaces(id: "g", faces: 64),
            .setComponentWrapScalar(id: "g", property: .offset, value: 0.01),
        ] {
            var history = DocumentHistory(document: source)
            try history.apply(command)
            let changed = history.document
            XCTAssertNotEqual(changed.encoded(), source.encoded())
            let originalNodes = try XMLDocument(data: source.modelXML).nodes(forXPath: "/canvas/nodes").map(\.xmlString)
            let changedNodes = try XMLDocument(data: changed.modelXML).nodes(forXPath: "/canvas/nodes").map(\.xmlString)
            XCTAssertEqual(changedNodes, originalNodes)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            XCTAssertThrowsError(try changed.editorContents())
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }

}
