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

    func testEveryVerifiedTemplateHasAuthoredSegmentsWithExactEndpoints() throws {
        for type in ["Biped", "Quadruped", "Bird", "Fish", "Snake", "Insect", "Spider"] {
            let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: type))
            XCTAssertTrue(hierarchy.bones.allSatisfy { $0.segment != nil }, type)
            XCTAssertEqual(hierarchy.roots.first?.segment, hierarchy.bones.first?.segment)
        }
        let biped = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let root = try XCTUnwrap(biped.roots.first?.segment)
        XCTAssertEqual(root.start, SIMD3(0, 0, 0))
        XCTAssertEqual(root.end, SIMD3(0, 0.9, 0))
        let hair = try XCTUnwrap(biped.bones.first { $0.name == "HairBack1" }?.segment)
        XCTAssertEqual(hair.start, SIMD3(0, 1.8, -0.08))
        XCTAssertEqual(hair.end, SIMD3(0, 1.65, -0.12))
    }

    func testUnavailableSegmentsDoNotPreventHierarchyBrowsing() throws {
        let xml = """
            <rig type="Test">
            <bone name="Root"/>
            <bone name="Nonfinite" parent="Root"><position x="0" y="nan" z="0"/><endPosition x="0" y="1" z="0"/></bone>
            <bone name="Zero" parent="Root"><position x="0" y="0" z="0"/><endPosition x="0" y="0" z="0"/></bone>
            <bone name="Huge" parent="Root"><position x="1e100" y="0" z="0"/><endPosition x="0" y="1" z="0"/></bone>
            <bone name="Partial" parent="Root"><position x="0" y="0"/><endPosition x="0" y="1" z="0"/></bone>
            </rig>
            """
        let hierarchy = try RigTemplateHierarchy.parse(Data(xml.utf8), expectedType: "Test")
        XCTAssertEqual(hierarchy.roots.first?.children?.map(\.name), ["Nonfinite", "Zero", "Huge", "Partial"])
        XCTAssertTrue(hierarchy.bones.allSatisfy { $0.segment == nil })
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
