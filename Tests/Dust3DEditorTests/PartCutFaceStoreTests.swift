import Dust3DDocument
import Dust3DKit
import Foundation
import XCTest
import simd

@testable import Dust3DEditor

final class PartCutFaceStoreTests: XCTestCase {
    private let owner = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private let profile = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
    private func document(rotationText: String? = nil) throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let nodes = [
            "{11111111-1111-4111-8111-111111111111}", "{22222222-2222-4222-8222-222222222222}",
            "{33333333-3333-4333-8333-333333333333}",
        ]
        for (index, id) in nodes.enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: owner, componentID: index == 0 ? "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}" : nil,
                    position: .init(x: 0.5, y: 0.5, z: Double(index)), radius: 0.1))
        }
        document = try document.applying(
            .addEdge(id: "{44444444-4444-4444-8444-444444444444}", from: nodes[0], to: nodes[1]))
        document = try document.applying(
            .addEdge(id: "{55555555-5555-4555-8555-555555555555}", from: nodes[1], to: nodes[2]))
        let profileNodes = ["{66666666-6666-4666-8666-666666666666}", "{77777777-7777-4777-8777-777777777777}"]
        for (index, id) in profileNodes.enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: profile, componentID: index == 0 ? "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}" : nil,
                    position: .init(x: 2 + Double(index) * 0.4, y: 2, z: 1), radius: 0.05))
        }
        document = try document.applying(
            .addEdge(id: "{88888888-8888-4888-8888-888888888888}", from: profileNodes[0], to: profileNodes[1]))
        let model = try XMLDocument(data: document.modelXML)
        var attributes = [(owner, "cutFace", "future"), (profile, "target", "CutFace")]
        if let rotationText { attributes.append((owner, "cutRotation", rotationText)) }
        for (id, name, text) in attributes {
            let element = try XCTUnwrap(try model.nodes(forXPath: "//part[@id='\(id)']").first as? XMLElement)
            let attribute = XMLNode(kind: .attribute)
            attribute.name = name
            attribute.stringValue = text
            element.addAttribute(attribute)
        }
        let bytes = model.xmlData(options: [.nodePreserveAll])
        let header = "<ds3><model name='model.xml' offset='0' size='\(bytes.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + bytes)
    }
    private func assertFinite(_ mesh: Mesh) {
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertTrue(
            mesh.vertices.allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                    && abs(simd_length($0.normal) - 1) < 0.0001
            })
    }
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Cut-face action or mesh generation did not settle")
    }
    @MainActor private func assertHistory(
        original: Dust3DDocument, expectDifferent: Bool = true, apply: @MainActor (EditorStore) -> Void
    ) async throws {
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectPart(owner)
        try await settle(store)
        let baseline = try XCTUnwrap(store.mesh)
        let camera = store.cameraReset
        apply(store)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.previewState.errorMessage)
        let changed = try XCTUnwrap(store.mesh)
        assertFinite(changed)
        if expectDifferent { XCTAssertNotEqual(changed.vertices.map(\.position), baseline.vertices.map(\.position)) }
        XCTAssertEqual(store.snapshot?.selectedPartID, owner)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(publications, 1)
        let bytes = try XCTUnwrap(store.snapshot?.document.encoded())
        let preview = store.previewRevision
        apply(store)
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
    func testLegacyCommaRotationMatchesActualCoreOutput() throws {
        let comma = try document(rotationText: "0,5")
        let dot = try document(rotationText: "0.5")
        XCTAssertEqual(try comma.editorContents().parts.first?.cutRotation, 0.5)
        let commaMesh = try MeshLoader.load(data: comma.encoded())
        let dotMesh = try MeshLoader.load(data: dot.encoded())
        assertFinite(commaMesh)
        XCTAssertEqual(commaMesh.vertices.map(\.position), dotMesh.vertices.map(\.position))
        XCTAssertEqual(commaMesh.vertices.map(\.normal), dotMesh.vertices.map(\.normal))
    }

    @MainActor func testAllPresetsRegenerateAndRestoreExactHistory() async throws {
        for preset in CutFacePreset.allCases {
            try await assertHistory(original: document(), expectDifferent: preset != .quad) {
                $0.setPartCutFace(owner, selection: .preset(preset))
            }
        }
    }
    @MainActor func testLinkedProfileChangesGeneratedCrossSectionWithExactHistory() async throws {
        try await assertHistory(original: document()) { $0.setPartCutFace(owner, selection: .linkedPart(profile)) }
    }
    @MainActor func testRotationChangesGeometryAndRestoresExactHistory() async throws {
        let original = try document().applying(.setPartCutFace(id: owner, selection: .preset(.triangle)))
        try await assertHistory(original: original) { $0.setPartCutRotation(owner, rotation: "0.25") }
        for rotation in [-1.0, Double(Float.leastNonzeroMagnitude), 1.0] {
            let changed = try original.applying(.setPartCutRotation(id: owner, rotation: rotation))
            assertFinite(try MeshLoader.load(data: changed.encoded()))
        }
    }
    @MainActor func testRotationInputRejectsUnderflowWithoutLosingExplicitZero() async throws {
        let original = try document().applying(.setPartCutRotation(id: owner, rotation: 0.25))
        let store = EditorStore()
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        let revision = store.previewRevision
        for text in [
            "", "nan", "inf", "5e-324", "1e-50", "2.2250738585072014e-308", "1e-999", "-1e-999", "0x1p-9999", "-1.001",
            "1.001",
        ] {
            store.setPartCutRotation(owner, rotation: text)
            try await settle(store)
            XCTAssertTrue(store.errorMessage?.contains("-1 to 1") == true)
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(store.previewRevision, revision)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        }
        store.setPartCutRotation(owner, rotation: "0,25")
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.setPartCutRotation(owner, rotation: "0e-999")
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.snapshot?.parts.first?.cutRotation, 0)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
    }
}
