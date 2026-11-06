import Foundation
import XCTest

@testable import Dust3DKit

final class RigTemplateHierarchyTests: XCTestCase {
    func testAllPinnedTemplatesExposeOrderedNamesAndParentsWithoutGeneration() throws {
        let counts = ["Biped": 35, "Quadruped": 22, "Bird": 30, "Fish": 17, "Snake": 14, "Insect": 24, "Spider": 30]
        for (type, count) in counts {
            let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: type))
            XCTAssertEqual(hierarchy.type, type)
            XCTAssertEqual(hierarchy.bones.count, count)
            XCTAssertEqual(hierarchy.roots.map(\.name), ["Root"])
            XCTAssertFalse(hierarchy.description.isEmpty)
            XCTAssertEqual(Set(hierarchy.bones.map { Data($0.name.utf8) }).count, count)
            let names = Set(hierarchy.bones.map { Data($0.name.utf8) })
            for bone in hierarchy.bones where !bone.parentName.isEmpty {
                XCTAssertTrue(names.contains(Data(bone.parentName.utf8)))
            }
        }
        XCTAssertNil(try RigTemplateHierarchy.load(sourceType: nil))
        XCTAssertNil(try RigTemplateHierarchy.load(sourceType: "None"))
        XCTAssertThrowsError(try RigTemplateHierarchy.load(sourceType: "future")) {
            XCTAssertEqual($0 as? RigTemplateResourceError, .unsupportedType("future"))
        }
    }

    func testHierarchyResolvesForwardParentsAndPreservesExactUnicodeAndSiblingOrder() throws {
        let xml = """
            <rig type="Test"><description>Exact hierarchy</description>
            <bone name="é" parent="Root"/><bone name="é" parent="Root"/>
            <bone name="Leaf" parent="é"/><bone name="Root" parent=""/>
            <bone name="Orphan" parent="missing"/></rig>
            """
        let result = try RigTemplateHierarchy.parse(Data(xml.utf8), expectedType: "Test")
        XCTAssertEqual(
            result.bones.map(\.name).map { Data($0.utf8) }, ["é", "é", "Leaf", "Root", "Orphan"].map { Data($0.utf8) })
        XCTAssertEqual(result.roots.map(\.name), ["Root", "Orphan"])
        let root = try XCTUnwrap(result.roots.first)
        XCTAssertEqual(root.children?.map { Data($0.name.utf8) }, ["é", "é"].map { Data($0.utf8) })
        XCTAssertEqual(root.children?.first?.children?.map(\.name), ["Leaf"])
    }

    func testInvalidAndCyclicMetadataIsRejectedWithoutPartialHierarchy() {
        let invalid = [
            "<rig type='Test'><bone name='A' parent='B'/><bone name='B' parent='A'/></rig>",
            "<rig type='Test'><bone name='A'/><bone name='A'/></rig>",
            "<rig type='Test'><bone name='A' parent='A'/></rig>",
            "<rig type='Test'><bone name=''/></rig>",
            "<rig type='Other'><bone name='Root'/></rig>",
            "<canvas/>", "<rig", "<!DOCTYPE rig [<!ENTITY x 'expanded'>]><rig type='Test'><bone name='&x;'/></rig>",
        ]
        for xml in invalid {
            XCTAssertThrowsError(try RigTemplateHierarchy.parse(Data(xml.utf8), expectedType: "Test"), xml)
        }
        XCTAssertThrowsError(try RigTemplateHierarchy.parse(Data(repeating: 32, count: 16385), expectedType: "Test"))
    }
}
