import Dust3DDocument
import Dust3DKit
import XCTest

final class ComponentStructureCompatibilityTests: XCTestCase {
    func testGroupingReparentingAndUngroupingRetainDisjointUnionGeometryAndExactUndo() throws {
        let first = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
        let second = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        let group = "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}"
        let outer = "{ffffffff-ffff-4fff-8fff-ffffffffffff}"
        var original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (node, part, component, x) in [
            ("{11111111-1111-4111-8111-111111111111}", "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", first, 0.5),
            ("{22222222-2222-4222-8222-222222222222}", "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", second, 3.0),
        ] {
            original = try original.applying(
                .addNode(
                    id: node, partID: part, componentID: component, position: .init(x: x, y: 0.5, z: 0.5), radius: 0.1))
        }
        let baseline = try MeshLoader.load(data: original.encoded())
        XCTAssertEqual(baseline.triangleCount, 32)
        var history = DocumentHistory(document: original)
        for command: DocumentCommand in [
            .groupComponents(ids: [first], groupID: group), .reparentComponent(id: second, parentID: group),
            .groupComponents(ids: [group], groupID: outer), .ungroupComponent(id: group), .ungroupComponent(id: outer),
        ] {
            try history.apply(command)
            let reopened = try Dust3DDocument(data: history.document.encoded())
            let mesh = try MeshLoader.load(data: reopened.encoded())
            XCTAssertEqual(mesh.nodeCount, 2)
            XCTAssertEqual(mesh.partCount, 2)
            XCTAssertEqual(mesh.triangleCount, 32)
            for axis in 0..<3 {
                XCTAssertTrue(mesh.vertices.allSatisfy { $0.position[axis].isFinite && $0.normal[axis].isFinite })
                XCTAssertEqual(
                    try XCTUnwrap(mesh.vertices.map { $0.position[axis] }.min()),
                    try XCTUnwrap(baseline.vertices.map { $0.position[axis] }.min()), accuracy: 0.00001)
                XCTAssertEqual(
                    try XCTUnwrap(mesh.vertices.map { $0.position[axis] }.max()),
                    try XCTUnwrap(baseline.vertices.map { $0.position[axis] }.max()), accuracy: 0.00001)
            }
        }
        for _ in 0..<5 { XCTAssertTrue(history.undo()) }
        XCTAssertEqual(history.document.encoded(), original.encoded())
        for _ in 0..<5 { XCTAssertTrue(history.redo()) }
        XCTAssertEqual(try history.document.components().map(\.id), [first, second])
    }
}
