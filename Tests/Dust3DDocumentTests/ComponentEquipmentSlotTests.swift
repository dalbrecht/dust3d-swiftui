import Dust3DDocument
import Foundation
import XCTest

final class ComponentEquipmentSlotTests: XCTestCase {
    private func makeDocument(name: String = "vest") throws -> Dust3DDocument {
        let xml = """
            <canvas future='preserve'><parts>
            <part id='p' target='Model'/><part id='cut' target='CutFace'/>
            </parts><components>
            <component id='a' linkDataType='partId' linkData='p' name='\(name)' future='keep'>
            <vendorData>opaque</vendorData><!--keep-comment-->
            </component>
            <component id='group' name='other'/>
            <component id='non-model' linkDataType='partId' linkData='cut'/>
            <component id='missing-part' linkDataType='partId' linkData='missing'/>
            </components></canvas>
            """
        return try Dust3DDocument(snapshotXML: Data(xml.utf8))
    }

    func testAddingAndRepeatingAnAssignment() throws {
        let source = try makeDocument()
        let edited = try source.applying(.setComponentEquipmentSlot(id: "a", slot: "  armor/2  "))
        let reopened = try Dust3DDocument(data: edited.encoded())
        let component = try XCTUnwrap(reopened.components().first { $0.id == "a" })
        XCTAssertEqual(component.name, "vest @armor/2")
        XCTAssertEqual(component.equipmentSlot, "armor/2")
        let repeated = try reopened.applying(.setComponentEquipmentSlot(id: "a", slot: " armor/2 "))
        XCTAssertEqual(repeated.encoded(), reopened.encoded())
    }

    func testReplacingAndClearingUsesFinalMarkerAndPreservesBaseAndOpaqueXML() throws {
        let source = try makeDocument(name: "  vest @label  @armor/1")
        let edited = try source.applying(.setComponentEquipmentSlot(id: "a", slot: "armor/2"))
        let editedComponent = try XCTUnwrap(edited.components().first { $0.id == "a" })
        XCTAssertEqual(editedComponent.name, "  vest @label  @armor/2")
        XCTAssertEqual(editedComponent.equipmentSlot, "armor/2")

        let cleared = try edited.applying(.setComponentEquipmentSlot(id: "a", slot: "  "))
        let clearedComponents = try cleared.components()
        XCTAssertEqual(clearedComponents.first { $0.id == "a" }?.name, "  vest @label ")
        XCTAssertEqual(clearedComponents.filter { $0.id != "a" }, try source.components().filter { $0.id != "a" })
        let xml = try XMLDocument(data: cleared.modelXML)
        let editedElement = try XCTUnwrap(xml.nodes(forXPath: "//component[@id='a']").first as? XMLElement)
        XCTAssertEqual(editedElement.attribute(forName: "future")?.stringValue, "keep")
        XCTAssertEqual(editedElement.elements(forName: "vendorData").first?.stringValue, "opaque")
        XCTAssertTrue(editedElement.xmlString.contains("<!--keep-comment-->"))
        XCTAssertEqual(xml.rootElement()?.attribute(forName: "future")?.stringValue, "preserve")

        let plain = try makeDocument(name: "  vest ")
        let assigned = try plain.applying(.setComponentEquipmentSlot(id: "a", slot: "armor/2"))
        let clearedPlain = try assigned.applying(.setComponentEquipmentSlot(id: "a", slot: ""))
        XCTAssertEqual(try clearedPlain.components().first { $0.id == "a" }?.name, "  vest ")
        XCTAssertNil(try clearedPlain.components().first { $0.id == "a" }?.equipmentSlot)
    }

    func testCanonicallyEquivalentSlotSpellingPreservesNewUTF8Bytes() throws {
        let composed = "arm\u{00E9}/2"
        let decomposed = "arme\u{0301}/2"
        XCTAssertEqual(composed, decomposed)
        let original = try makeDocument(name: "Vest @" + composed)
        let edited = try original.applying(.setComponentEquipmentSlot(id: "a", slot: decomposed))
        let component = try XCTUnwrap(edited.components().first { $0.id == "a" })
        XCTAssertEqual(Array(try XCTUnwrap(component.equipmentSlot).utf8), Array(decomposed.utf8))
        XCTAssertNotEqual(edited.encoded(), original.encoded())
    }

    func testEquipmentEditsRejectComponentsWithoutALinkedModelPart() throws {
        let source = try makeDocument()
        for id in ["group", "non-model", "missing-part"] {
            XCTAssertThrowsError(try source.applying(.setComponentEquipmentSlot(id: id, slot: "armor/2")), id)
        }
    }
}
