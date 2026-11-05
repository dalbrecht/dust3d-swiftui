import CryptoKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private enum MultiWrapAdmission {
    enum Failure: Error { case unreviewedInput, unexpectedImportedSelection }
    static func check(_ data: Data) throws {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard
            [
                (1091, "3c5703d1578e4507e8895555e1f6f39d8137782bfe6e67fb6bb96e7247adbb9e"),
                (1091, "52b790c568f104c325ecc6b8a3658bb062c06834bc53bea020f66429aefce43a"),
                (1137, "4f91a39ccf3bfbe62e388f4bb2f628241f3e2b20d262009f9155e285db6d3a60"),
            ]
            .contains(where: { $0.0 == data.count && $0.1 == hash })
        else { throw Failure.unreviewedInput }
    }
}
private struct ReviewedMultiWrapPreview: EditorPreviewServing {
    private let service = EditorPreviewService()
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        try MultiWrapAdmission.check(data)
        return try await service.generate(data, scopeID: scopeID)
    }
    func reset(scopeID: UUID) async throws { try await service.reset(scopeID: scopeID) }
}
private struct ReviewedMultiWrapBaker: ArchiveTextureBaking {
    private let service = ArchiveTextureBakingService()
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        try MultiWrapAdmission.check(data)
        return try await service.load(data: data, options: options, limits: limits)
    }
}
private struct ReviewedMultiWrapImportedSelection: ArchiveImportedMaterialLoading {
    private let service = ArchiveImportedMaterialService()
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        try MultiWrapAdmission.check(data)
        return try await service.loadIfPresent(data: data, limits: limits)
    }
    func selectForPreparation(
        data: Data, limits: ImportedMaterialRenderLimits, inspectionLimits: ImportedSurfaceOptions
    ) async throws -> ArchiveImportedMaterialSelection {
        try MultiWrapAdmission.check(data)
        let selection = try await service.selectForPreparation(
            data: data, limits: limits, inspectionLimits: inspectionLimits)
        guard case .procedural = selection else { throw MultiWrapAdmission.Failure.unexpectedImportedSelection }
        return selection
    }
}

/// Ordinary bounded two-sphere garments: no imported assets, edges, bindings, faults or forced flags. Cloth may generate fold placement.
@MainActor final class ComponentWrappingBatchNativeTests: XCTestCase {
    private enum Failure: Error { case unreviewedFixture, timeout }
    private let ids: Set<String> = ["{00000301-0000-4000-8000-000000000301}", "{00000302-0000-4000-8000-000000000302}"]
    private func fixture(_ expected: Bool) throws -> Data {
        let text =
            expected
            ? "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4Ng0KPGRzMz48bW9kZWwgbmFtZT0ibW9kZWwueG1sIiBvZmZzZXQ9IjAiIHNpemU9IjEwMDUiLz48L2RzMz48Y2FudmFzIG9yaWdpblg9Jy41JyBvcmlnaW5ZPScuNScgb3JpZ2luWj0nLjUnPjxub2Rlcz48bm9kZSBpZD0nezAwMDAxMDAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMTAwMX0nIHBhcnRJZD0nezAwMDAwMTAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMX0nIHg9Jy4yNScgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4xNScvPjxub2RlIGlkPSd7MDAwMDEwMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAxMDAyfScgcGFydElkPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScgeD0nLjc1JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjE1Jy8+PC9ub2Rlcz48ZWRnZXMvPjxwYXJ0cz48cGFydCBpZD0nezAwMDAwMTAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMX0nLz48cGFydCBpZD0nezAwMDAwMTAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMn0nLz48L3BhcnRzPjxjb21wb25lbnRzPjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMS0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDF9JyB3cmFwPSdDbG90aCcgd3JhcEZhY2VzPSc2NCcgd3JhcEtlZXA9J2ZhbHNlJyB3cmFwT2Zmc2V0PScuMDI1Jz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAxfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScvPjwvY29tcG9uZW50Pjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDJ9JyB3cmFwPSdDbG90aCcgd3JhcEZhY2VzPSc2NCcgd3JhcEtlZXA9J2ZhbHNlJyB3cmFwT2Zmc2V0PScuMDI1Jz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAyfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScvPjwvY29tcG9uZW50PjwvY29tcG9uZW50cz48L2NhbnZhcz4="
            : "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4Ng0KPGRzMz48bW9kZWwgbmFtZT0ibW9kZWwueG1sIiBvZmZzZXQ9IjAiIHNpemU9IjEwMDUiLz48L2RzMz48Y2FudmFzIG9yaWdpblg9Jy41JyBvcmlnaW5ZPScuNScgb3JpZ2luWj0nLjUnPjxub2Rlcz48bm9kZSBpZD0nezAwMDAxMDAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMTAwMX0nIHBhcnRJZD0nezAwMDAwMTAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMX0nIHg9Jy4yNScgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4xNScvPjxub2RlIGlkPSd7MDAwMDEwMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAxMDAyfScgcGFydElkPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScgeD0nLjc1JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjE1Jy8+PC9ub2Rlcz48ZWRnZXMvPjxwYXJ0cz48cGFydCBpZD0nezAwMDAwMTAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMX0nLz48cGFydCBpZD0nezAwMDAwMTAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMn0nLz48L3BhcnRzPjxjb21wb25lbnRzPjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMS0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDF9JyB3cmFwPSdDbG90aCcgd3JhcEZhY2VzPSc2NCcgd3JhcEtlZXA9J2ZhbHNlJyB3cmFwT2Zmc2V0PScuMDEyJz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAxfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScvPjwvY29tcG9uZW50Pjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDJ9JyB3cmFwPSdDbG90aCcgd3JhcEZhY2VzPSc2NCcgd3JhcEtlZXA9J2ZhbHNlJyB3cmFwT2Zmc2V0PScuMDEyJz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAyfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScvPjwvY29tcG9uZW50PjwvY29tcG9uZW50cz48L2NhbnZhcz4="
        let hash =
            expected
            ? "52b790c568f104c325ecc6b8a3658bb062c06834bc53bea020f66429aefce43a"
            : "3c5703d1578e4507e8895555e1f6f39d8137782bfe6e67fb6bb96e7247adbb9e"
        guard let data = Data(base64Encoded: text), data.count == 1091,
            SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash
        else { throw Failure.unreviewedFixture }
        return data
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<3000 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timeout
    }
    /// Keep every occurrence and winding; only cyclic starting corner/triangle ordering is normalized.
    private func triangles(_ mesh: IndexedMesh) -> [[UInt32]] {
        stride(from: 0, to: mesh.indices.count, by: 3).map { start in
            let corners = (0..<3).map { offset -> [UInt32] in
                let p = mesh.vertices[Int(mesh.indices[start + offset])].position
                return [p.x.bitPattern, p.y.bitPattern, p.z.bitPattern]
            }
            return (0..<3).map { offset in (0..<3).flatMap { corners[($0 + offset) % 3] } }
                .sorted { $0.lexicographicallyPrecedes($1) }[0]
        }.sorted { $0.lexicographicallyPrecedes($1) }
    }
    private func assertGarments(_ mesh: IndexedMesh) {
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertEqual(mesh.nodeCount, 2)
        XCTAssertEqual(mesh.partCount, 2)
        XCTAssertTrue(
            mesh.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite })
        // Both separate source regions must contribute generated surfaces.
        XCTAssertTrue(mesh.vertices.contains { $0.position.x < -0.1 })
        XCTAssertTrue(mesh.vertices.contains { $0.position.x > 0.1 })
    }
    func testActualBatchActionBuildsBothGarmentsAndMatchesIndependentArchiveWithHistoryAndReopen() async throws {
        let source = try fixture(false)
        let independent = try fixture(true)
        let store = EditorStore(
            preview: ReviewedMultiWrapPreview(), materialBaker: ReviewedMultiWrapBaker(),
            importedMaterialLoader: ReviewedMultiWrapImportedSelection())
        defer { store.stop() }
        await store.load(data: source)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        let before = try XCTUnwrap(store.mesh)
        assertGarments(before)
        store.selectComponents(ids)
        try await settle(store)
        let selected = try XCTUnwrap(store.snapshot)
        store.componentWrappingSelectionAction(.scalar(.offset, 0.025), target: .init(snapshot: selected))()
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertNil(store.materialIssue)
        let result = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(result.selectedComponentIDs, ids)
        let actual = try XCTUnwrap(store.mesh)
        assertGarments(actual)
        XCTAssertNotEqual(triangles(actual), triangles(before))
        try MultiWrapAdmission.check(independent)
        let expected = try MeshLoader.loadIndexed(data: independent)
        XCTAssertEqual(actual.triangleCount, expected.triangleCount)
        XCTAssertEqual(triangles(actual), triangles(expected))
        let saved = result.document.encoded()
        try MultiWrapAdmission.check(saved)
        let reopened = try MeshLoader.loadIndexed(data: saved)
        XCTAssertEqual(triangles(reopened), triangles(actual))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.snapshot?.canUndo == true)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        XCTAssertEqual(triangles(try XCTUnwrap(store.mesh)), triangles(actual))
    }
}
