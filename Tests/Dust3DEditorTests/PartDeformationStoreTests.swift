import Dust3DDocument
import Dust3DKit
import XCTest
import simd

@testable import Dust3DEditor

final class PartDeformationStoreTests: XCTestCase {
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
                    position: .init(x: 0.5, y: 0.5, z: Double(index)), radius: [0.1, 0.2, 0.15][index]))
        }
        document = try document.applying(
            .addEdge(id: "{44444444-4444-4444-8444-444444444444}", from: nodes[0], to: nodes[1]))
        return try document.applying(
            .addEdge(id: "{55555555-5555-4555-8555-555555555555}", from: nodes[1], to: nodes[2]))
    }
    func testBoundaryScalesGenerateFiniteMeshes() throws {
        let baseline = try document()
        for property in PartDeformationProperty.allCases {
            for value in [0.0, Double(Float.leastNonzeroMagnitude), 2.0] {
                let changed = try baseline.applying(
                    .setPartDeformationScale(id: part, property: property, value: value))
                let mesh = try MeshLoader.load(data: changed.encoded())
                XCTAssertGreaterThan(mesh.triangleCount, 0)
                XCTAssertTrue(
                    mesh.vertices.allSatisfy {
                        $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                            && abs(simd_length($0.normal) - 1) < 0.0001
                    })
            }
        }
    }
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Deformation edit or mesh generation did not settle")
    }
    @MainActor func testScaleEditsRegenerateKeepSelectionAndCameraAndRestoreExactHistory() async throws {
        let original = try document()
        for property in PartDeformationProperty.allCases {
            let store = EditorStore()
            defer { store.stop() }
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            await store.load(data: original.encoded())
            try await settle(store)
            store.selectPart(part)
            try await settle(store)
            let baseline = try XCTUnwrap(store.mesh)
            let camera = store.cameraReset
            store.setPartDeformationScale(part, property: property, value: "0.995")
            try await settle(store)
            XCTAssertNil(store.errorMessage)
            let changed = try XCTUnwrap(store.mesh)
            XCTAssertNotEqual(changed.vertices.map(\.position), baseline.vertices.map(\.position))
            XCTAssertTrue(
                changed.vertices.allSatisfy {
                    $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                        && abs(simd_length($0.normal) - 1) < 0.0001
                })
            XCTAssertEqual(store.snapshot?.selectedPartID, part)
            XCTAssertEqual(store.cameraReset, camera)
            XCTAssertEqual(publications, 1)
            let bytes = try XCTUnwrap(store.snapshot?.document.encoded())
            let preview = store.previewRevision
            store.setPartDeformationScale(part, property: property, value: "0.995")
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
    @MainActor func testUnifiedDeformationChangesTaperedGeometryAndInvalidScalesDoNotPublish() async throws {
        let original = try document().applying(.setPartDeformationScale(id: part, property: .width, value: 0.5))
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectPart(part)
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        let revision = store.previewRevision
        for text in [
            "", "nan", "inf", "-0.001", "2.001", "future", "5e-324", "1e-50", "2.2250738585072014e-308", "1e-310",
            "1e-999", "0x1p-9999",
        ] {
            store.setPartDeformationScale(part, property: .width, value: text)
            try await settle(store)
            XCTAssertTrue(store.errorMessage?.contains("0 to 2") == true)
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(store.previewRevision, revision)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        }
        store.setPartDeformationUnified(part, value: true)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        let changed = try XCTUnwrap(store.mesh)
        XCTAssertNotEqual(changed.vertices.map(\.position), baseline.vertices.map(\.position))
        XCTAssertEqual(store.snapshot?.parts.first?.isDeformationUnified, true)
        XCTAssertEqual(publications, 1)
        let bytes = store.snapshot?.document.encoded()
        store.setPartDeformationUnified(part, value: true)
        try await settle(store)
        XCTAssertEqual(publications, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), changed.vertices.map(\.position))
    }
}
