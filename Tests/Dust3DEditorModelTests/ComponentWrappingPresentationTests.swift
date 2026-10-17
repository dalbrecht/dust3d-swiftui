import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentWrappingPresentationTests: XCTestCase {
    private func source(_ attributes: String) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='g' \(attributes)/></components></canvas>"
                    .utf8))
    }
    func testKnownAndUnsupportedModesChooseOnlyApplicableFieldsWithoutEditingSource() throws {
        for (text, properties): (String, [ComponentWrappingScalarProperty]) in [
            ("", []), ("Future", []), ("Skin", [.offset, .smoothness]),
            ("Cloth", ComponentWrappingScalarProperty.allCases),
        ] {
            let document = try source("wrap='\(text)'")
            let before = document.encoded()
            let component = try XCTUnwrap(document.components().first)
            let presentation = ComponentWrappingPresentation(component: component)
            XCTAssertTrue(presentation.isAvailable)
            XCTAssertEqual(presentation.showsSettings, !properties.isEmpty)
            XCTAssertEqual(presentation.fields.map(\.property), properties)
            XCTAssertEqual(presentation.fields.map(\.id), properties)
            XCTAssertEqual(document.encoded(), before)
        }
    }
    func testLinkedOrOpaqueComponentsDoNotExposeGroupWrappingControls() throws {
        for attributes in ["linkDataType='partId' linkData='p'", "linkDataType='future' linkData='opaque'"] {
            let component = try XCTUnwrap(source("wrap='Cloth' \(attributes)").components().first)
            let presentation = ComponentWrappingPresentation(component: component)
            XCTAssertFalse(presentation.isAvailable)
            XCTAssertFalse(presentation.showsSettings)
            XCTAssertTrue(presentation.fields.isEmpty)
        }
    }
    func testClothFieldTitlesAndRangesMatchTheSupportedInspectorContract() throws {
        let component = try XCTUnwrap(source("wrap='Cloth'").components().first)
        let fields = ComponentWrappingPresentation(component: component).fields
        XCTAssertEqual(
            fields.map(\.title),
            ["Offset", "Smoothness", "Drape", "Drape length", "Open top", "Open bottom", "Thickness"])
        XCTAssertEqual(
            fields.map(\.rangeDescription), ["0–0.1", "0–0.15", "0–1.0", "0–0.5", "0–0.45", "0–0.45", "0–0.02"])
    }
    func testModeLabelsKeepTheDisabledChoiceVisible() {
        XCTAssertEqual(
            ComponentWrapMode.allCases.map { ComponentWrappingPresentation.modeTitle($0) }, ["None", "Skin", "Cloth"])
    }

}
