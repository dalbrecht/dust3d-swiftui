import Dust3DDocument
import Dust3DKit
import XCTest
import simd

@testable import Dust3DEditor

final class PartModifierStoreTests: XCTestCase {
    private let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let nodes = [
            "{11111111-1111-4111-8111-111111111111}", "{22222222-2222-4222-8222-222222222222}",
            "{33333333-3333-4333-8333-333333333333}",
        ]
        for (index, id) in nodes.enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: part, componentID: index == 0 ? "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}" : nil,
                    position: .init(x: 0.5, y: 0.5, z: Double(index)), radius: 0.1))
        }
        document = try document.applying(
            .addEdge(id: "{44444444-4444-4444-8444-444444444444}", from: nodes[0], to: nodes[1]))
        return try document.applying(
            .addEdge(id: "{55555555-5555-4555-8555-555555555555}", from: nodes[1], to: nodes[2]))
    }
    func testHardJoinChangesTheActualIntersectingPartSeam() throws {
        var original = try document()
        let otherPart = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
        let first = "{66666666-6666-4666-8666-666666666666}"
        let second = "{77777777-7777-4777-8777-777777777777}"
        for (index, node) in [first, second].enumerated() {
            original = try original.applying(
                .addNode(
                    id: node, partID: otherPart,
                    componentID: index == 0 ? "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}" : nil,
                    position: .init(
                        x: Double(index) * 2 - 0.5, y: 0.55 + Double(index) * 0.1, z: 0.85 + Double(index) * 0.3),
                    radius: 0.15))
        }
        original = try original.applying(
            .addEdge(
                id: "{88888888-8888-4888-8888-888888888888}", from: first, to: second))
        for partID in [part, otherPart] {
            original = try original.applying(.setPartModifier(id: partID, property: .subdivision, value: true))
        }
        let hard = try original.applying(.setPartModifier(id: otherPart, property: .hardJoin, value: true))
        let smoothMesh = try MeshLoader.load(data: original.encoded())
        let hardMesh = try MeshLoader.load(data: hard.encoded())
        XCTAssertGreaterThan(smoothMesh.triangleCount, 0)
        XCTAssertGreaterThan(hardMesh.triangleCount, 0)
        XCTAssertFalse(
            smoothMesh.vertices.map(\.position) == hardMesh.vertices.map(\.position),
            "The fixture must exercise smooth seam recombination")
        XCTAssertTrue(
            hardMesh.vertices.allSatisfy { vertex in
                (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                    && abs(simd_length(vertex.normal) - 1) < 0.0001
            })
    }
    func testShapeModifierCombinationsProduceFiniteNormalizedMeshes() throws {
        let baseline = try document()
        let properties: [PartModifierProperty] = [.subdivision, .chamfer, .roundedEnds, .interpolation]
        for mask in 0..<16 {
            var changed = baseline
            for (index, property) in properties.enumerated() {
                changed = try changed.applying(
                    .setPartModifier(id: part, property: property, value: mask & (1 << index) != 0))
            }
            let mesh = try MeshLoader.load(data: changed.encoded())
            XCTAssertGreaterThan(mesh.triangleCount, 0, "Combination \(mask)")
            XCTAssertTrue(
                mesh.vertices.allSatisfy { vertex in
                    (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                        && abs(simd_length(vertex.normal) - 1) < 0.0001
                }, "Combination \(mask)")
        }
    }
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Part modifier or mesh generation did not settle")
    }
    @MainActor func testEveryModifierRegeneratesKeepsSelectionAndCameraAndRestoresExactHistory() async throws {
        let original = try document()
        for property in PartModifierProperty.allCases {
            let store = EditorStore()
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            store.selectPart(part)
            try await settle(store)
            let baseline = try XCTUnwrap(store.mesh)
            let camera = store.cameraReset
            let revision = store.previewRevision
            store.setPartModifier(part, property: property, value: !property.defaultValue)
            try await settle(store)
            XCTAssertNil(store.errorMessage, property.rawValue)
            let changed = try XCTUnwrap(store.mesh)
            XCTAssertGreaterThan(changed.triangleCount, 0)
            XCTAssertTrue(
                changed.vertices.allSatisfy { vertex in
                    (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                        && abs(simd_length(vertex.normal) - 1) < 0.0001
                })
            if property != .hardJoin {
                XCTAssertNotEqual(
                    changed.vertices.map(\.position), baseline.vertices.map(\.position), property.rawValue)
            }
            XCTAssertEqual(store.snapshot?.selectedPartID, part)
            XCTAssertEqual(store.snapshot?.parts.first?.modifierValue(property), !property.defaultValue)
            XCTAssertEqual(store.cameraReset, camera)
            XCTAssertGreaterThan(store.previewRevision, revision)
            XCTAssertEqual(publications, 1)
            let bytes = store.snapshot?.document.encoded()
            let preview = store.previewRevision
            store.setPartModifier(part, property: property, value: !property.defaultValue)
            try await settle(store)
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(store.previewRevision, preview)
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
            XCTAssertEqual(store.mesh?.vertices.map(\.position), baseline.vertices.map(\.position))
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
            XCTAssertEqual(store.mesh?.vertices.map(\.position), changed.vertices.map(\.position))
        }
    }
}
