#if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
    import Foundation
    import XCTest
    @testable import Dust3DKit

    final class RigTemplateMeshTests: XCTestCase {
        func testEveryPinnedTemplateReturnsOwnedCompleteGeometry() throws {
            let counts = [
                "Biped": 35, "Bird": 30, "Fish": 17, "Insect": 24, "Quadruped": 22, "Snake": 14,
                "Spider": 30,
            ]
            for (type, count) in counts {
                let result = try XCTUnwrap(RigTemplateMesh.load(sourceType: type, selectedBoneName: "Root"))
                XCTAssertEqual(result.boneNames.count, count)
                XCTAssertEqual(result.vertices.count, count * 1764)
                XCTAssertEqual(result.vertices.filter { $0.role == .selectedBone }.count, 36)
                XCTAssertTrue(result.vertices.allSatisfy { $0.boneIndex >= 0 && $0.boneIndex < count })
                XCTAssertTrue(
                    result.vertices.allSatisfy { vertex in
                        (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                    })
                let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: type))
                XCTAssertEqual(
                    result.boneNames.map { Data($0.utf8) }, hierarchy.bones.map { Data($0.name.utf8) })
            }
            XCTAssertNil(try RigTemplateMesh.load(sourceType: nil))
            XCTAssertNil(try RigTemplateMesh.load(sourceType: "None"))
        }

        func testRepeatedResultsRemainIndependentAndResourceErrorsRetainTheirCause() throws {
            let first = try XCTUnwrap(RigTemplateMesh.load(sourceType: "Snake", selectedBoneName: "Root"))
            let before = first.vertices.map(\.position)
            let second = try XCTUnwrap(
                RigTemplateMesh.load(sourceType: "Bird", selectedBoneName: "unknown"))
            XCTAssertEqual(first.vertices.map(\.position), before)
            XCTAssertEqual(second.vertices.filter { $0.role == .selectedBone }.count, 0)
            XCTAssertThrowsError(try RigTemplateMesh.load(sourceType: "unknown"))
        }

        func testExactUnicodeSelectionAndMalformedPositions() throws {
            func xml(_ position: String = "<position x='0' y='0' z='0'/>") -> Data {
                Data(
                    """
                    <rig type='Test'><bone name='é'>\(position)<endPosition x='0' y='1' z='0'/></bone>
                    <bone name='é'><position x='1' y='0' z='0'/><endPosition x='1' y='1' z='0'/></bone></rig>
                    """.utf8)
            }
            let result = try RigTemplateMesh.parse(xml(), expectedType: "Test", selectedBoneName: "é")
            XCTAssertEqual(result.boneNames.map { Data($0.utf8) }, ["é", "é"].map { Data($0.utf8) })
            let selected = result.vertices.filter { $0.role == .selectedBone }
            XCTAssertEqual(selected.count, 36)
            XCTAssertTrue(selected.allSatisfy { $0.boneIndex == 0 })
            for vertex in result.vertices {
                let squared = (0..<3).reduce(Float.zero) { $0 + vertex.normal[$1] * vertex.normal[$1] }
                XCTAssertEqual(squared, 1, accuracy: 0.00001)
            }
            for position in [
                "", "<position x='0' y='0'/>", "<position x='nan' y='0' z='0'/>",
                "<position x='1000001' y='0' z='0'/>",
                "<position x='0' y='0' z='0'/><position x='0' y='0' z='0'/>",
            ] {
                XCTAssertThrowsError(try RigTemplateMesh.parse(xml(position), expectedType: "Test")) {
                    XCTAssertNotNil($0 as? RigTemplateHierarchyError)
                }
            }
        }

        @MainActor
        func testCancelledTaskRejectsBeforeNativePublication() async {
            let task = Task.detached {
                withUnsafeCurrentTask { $0?.cancel() }
                return try RigTemplateMesh.load(sourceType: "Snake")
            }
            do {
                _ = try await task.value
                XCTFail("Cancelled task must not publish geometry")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
        }

        func testDisplayCopyRetainsGeometryAndMapsSemanticRoles() throws {
            let raw = try XCTUnwrap(RigTemplateMesh.load(sourceType: "Snake", selectedBoneName: "Root"))
            let bone = SIMD4<Float>(0.1, 0.2, 0.3, 1)
            let selected = SIMD4<Float>(0.4, 0.5, 0.6, 1)
            let ring = SIMD4<Float>(0.7, 0.8, 0.9, 1)
            let display = try raw.displayMesh(boneColor: bone, selectedBoneColor: selected, ringColor: ring)
            XCTAssertEqual(display.vertices.count, raw.vertices.count)
            for (source, vertex) in zip(raw.vertices, display.vertices) {
                XCTAssertEqual(source.position, vertex.position)
                XCTAssertEqual(source.normal, vertex.normal)
                let expected = source.role == .bone ? bone : source.role == .selectedBone ? selected : ring
                XCTAssertEqual(vertex.color, expected)
            }
            XCTAssertThrowsError(
                try raw.displayMesh(
                    boneColor: SIMD4<Float>(.nan, 0, 0, 1), selectedBoneColor: selected, ringColor: ring))
        }
    }
#endif
