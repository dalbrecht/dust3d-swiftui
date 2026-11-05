import CryptoKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

// OUTSIDE executable tests pending independent source/hash review. Only the three fixed ordinary archives below.
private enum DeletionNativeAdmission {
    enum Failure: Error { case unreviewedInput, timeout, unexpectedImportedSelection }
    static let archives: [(String, Int, String)] = [
        ("source", 1039, "095705f0052b948a8c98a477faecc8ac9833ac612e8774a5da775cc34e9258ad"),
        ("remainder", 666, "3aafbc9c2e51366ed41b7798adeb23fe8ef887763c1023629caa4c42b4d08a9b"),
        ("empty", 256, "0cb478b7ba6841a45af6f8da5c5bd1a9144368ec362fd89426cb1b7779828473"),
    ]
    static func check(_ data: Data) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard archives.contains(where: { $0.1 == data.count && $0.2 == digest }) else {
            throw Failure.unreviewedInput
        }
    }
    static func fixture(_ name: String) throws -> Data {
        let text: String
        switch name {
        case "source":
            text =
                "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4NQ0KPGRzMz48bW9kZWwgbmFtZT0nbW9kZWwueG1sJyBvZmZzZXQ9JzAnIHNpemU9Jzk1NCcvPjwvZHMzPjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7MDAwMDEwMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAxMDAxfScgcGFydElkPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScgeD0nLjI1JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjE1Jy8+PG5vZGUgaWQ9J3swMDAwMTAwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDEwMDJ9JyBwYXJ0SWQ9J3swMDAwMDEwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAxMDJ9JyB4PScuNzUnIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMTUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScvPjxwYXJ0IGlkPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezAwMDAwMzAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDMwMX0nIG5hbWU9J0xlZnQnIGNvbWJpbmVNb2RlPSdVbmNvbWJpbmVkJz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAxfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScvPjwvY29tcG9uZW50Pjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDJ9JyBuYW1lPSdSaWdodCcgY29tYmluZU1vZGU9J1VuY29tYmluZWQnPjxjb21wb25lbnQgaWQ9J3swMDAwMDIwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAyMDJ9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3swMDAwMDEwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAxMDJ9Jy8+PC9jb21wb25lbnQ+PC9jb21wb25lbnRzPjwvY2FudmFzPg=="
        case "remainder":
            text =
                "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTA4DQo8P3htbCB2ZXJzaW9uPSIxLjAiPz48ZHMzPjxtb2RlbCBuYW1lPSdtb2RlbC54bWwnIG9mZnNldD0nMCcgc2l6ZT0nNTU4Jy8+PC9kczM+PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNhbnZhcyBvcmlnaW5YPScuNScgb3JpZ2luWT0nLjUnIG9yaWdpblo9Jy41Jz48bm9kZXM+PG5vZGUgaWQ9J3swMDAwMTAwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDEwMDJ9JyBwYXJ0SWQ9J3swMDAwMDEwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAxMDJ9JyB4PScuNzUnIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMTUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezAwMDAwMzAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDMwMn0nIG5hbWU9J1JpZ2h0JyBjb21iaW5lTW9kZT0nVW5jb21iaW5lZCc+PGNvbXBvbmVudCBpZD0nezAwMDAwMjAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDIwMn0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0nezAwMDAwMTAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMn0nLz48L2NvbXBvbmVudD48L2NvbXBvbmVudHM+PC9jYW52YXM+"
        case "empty":
            text =
                "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTI1DQo8P3htbCB2ZXJzaW9uPSIxLjAiIHN0YW5kYWxvbmU9InllcyI/PjxkczM+PG1vZGVsIG5hbWU9J21vZGVsLnhtbCcgb2Zmc2V0PScwJyBzaXplPScxMzEnLz48L2RzMz48P3htbCB2ZXJzaW9uPSIxLjAiIHN0YW5kYWxvbmU9InllcyI/PjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzLz48ZWRnZXMvPjxwYXJ0cy8+PGNvbXBvbmVudHMvPjwvY2FudmFzPg=="
        default: throw Failure.unreviewedInput
        }
        guard let data = Data(base64Encoded: text) else { throw Failure.unreviewedInput }
        try check(data)
        return data
    }
}
private struct ReviewedDeletionPreview: EditorPreviewServing {
    private let service = EditorPreviewService()
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        try DeletionNativeAdmission.check(data)
        return try await service.generate(data, scopeID: scopeID)
    }
    func reset(scopeID: UUID) async throws { try await service.reset(scopeID: scopeID) }
}
private struct ReviewedDeletionBaker: ArchiveTextureBaking {
    private let service = ArchiveTextureBakingService()
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws
        -> MeshWithBakedTextures
    {
        try DeletionNativeAdmission.check(data)
        return try await service.load(data: data, options: options, limits: limits)
    }
}
private struct ReviewedDeletionSourceBaker: ArchiveSourceTextureBaking {
    private let service = ArchiveSourceTextureBakingService()
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits)
        async throws -> SourceBakedMesh
    {
        try DeletionNativeAdmission.check(data)
        return try await service.load(data: data, options: options, limits: limits)
    }
}
private struct ReviewedDeletionImported: ArchiveImportedMaterialLoading {
    private let service = ArchiveImportedMaterialService()
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws
        -> ImportedMaterialRenderData?
    {
        try DeletionNativeAdmission.check(data)
        return try await service.loadIfPresent(data: data, limits: limits)
    }
    func selectForPreparation(
        data: Data, limits: ImportedMaterialRenderLimits,
        inspectionLimits: ImportedSurfaceOptions
    ) async throws -> ArchiveImportedMaterialSelection {
        try DeletionNativeAdmission.check(data)
        let value = try await service.selectForPreparation(
            data: data, limits: limits, inspectionLimits: inspectionLimits)
        guard case .procedural = value else {
            throw DeletionNativeAdmission.Failure.unexpectedImportedSelection
        }
        return value
    }
}
private struct NoDeletionCatalog: AnimationCatalogLoading {
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
}
@MainActor final class ComponentSubtreeDeletionNativeTests: XCTestCase {
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<3000 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw DeletionNativeAdmission.Failure.timeout
    }
    private func store() -> EditorStore {
        EditorStore(
            preview: ReviewedDeletionPreview(), materialBaker: ReviewedDeletionBaker(),
            importedMaterialLoader: ReviewedDeletionImported(),
            sourceMaterialBaker: ReviewedDeletionSourceBaker(),
            animationCatalog: NoDeletionCatalog())
    }
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
    private func triangles(_ mesh: Mesh) -> [[UInt32]] {
        stride(from: 0, to: mesh.vertices.count, by: 3).map { start in
            let corners = (0..<3).map { offset -> [UInt32] in
                let p = mesh.vertices[start + offset].position
                return [p.x.bitPattern, p.y.bitPattern, p.z.bitPattern]
            }
            return (0..<3).map { offset in (0..<3).flatMap { corners[($0 + offset) % 3] } }
                .sorted { $0.lexicographicallyPrecedes($1) }[0]
        }.sorted { $0.lexicographicallyPrecedes($1) }
    }
    func testActualContextualDeletionMatchesIndependentRemainderUndoReopenAndLegitimateEmptyPreview()
        async throws
    {
        let source = try DeletionNativeAdmission.fixture("source")
        let remainder = try DeletionNativeAdmission.fixture("remainder")
        let empty = try DeletionNativeAdmission.fixture("empty")
        let value = store()
        let independent = store()
        defer {
            value.stop()
            independent.stop()
        }
        await value.load(data: source)
        await independent.load(data: remainder)
        try await settle(value)
        try await settle(independent)
        XCTAssertNil(value.errorMessage)
        XCTAssertNil(value.materialIssue)
        let beforeBaked = try XCTUnwrap(value.bakedMesh).geometry
        XCTAssertGreaterThan(beforeBaked.triangleCount, 0)
        let before = try XCTUnwrap(value.mesh)
        XCTAssertEqual(before.nodeCount, 2)
        XCTAssertEqual(before.partCount, 2)
        XCTAssertGreaterThan(before.triangleCount, 0)
        XCTAssertNil(independent.errorMessage)
        XCTAssertNil(independent.materialIssue)
        let expectedBaked = try XCTUnwrap(independent.bakedMesh).geometry
        XCTAssertGreaterThan(expectedBaked.triangleCount, 0)
        let expected = try XCTUnwrap(independent.mesh)
        XCTAssertEqual(expected.nodeCount, 1)
        XCTAssertEqual(expected.partCount, 1)
        XCTAssertGreaterThan(expected.triangleCount, 0)
        value.componentDeletionAction(
            ComponentDeletionTarget(
                snapshot: try XCTUnwrap(value.snapshot),
                componentIDs: ["{00000301-0000-4000-8000-000000000301}"]))()
        try await settle(value)
        XCTAssertNil(value.errorMessage)
        XCTAssertNil(value.materialIssue)
        XCTAssertEqual(value.snapshot?.document.encoded(), remainder)
        XCTAssertEqual(triangles(try XCTUnwrap(value.bakedMesh).geometry), triangles(expectedBaked))
        XCTAssertEqual(triangles(try XCTUnwrap(value.mesh)), triangles(expected))
        let reopened = store()
        defer { reopened.stop() }
        await reopened.load(data: try XCTUnwrap(value.snapshot?.document.encoded()))
        try await settle(reopened)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertNil(reopened.materialIssue)
        XCTAssertEqual(triangles(try XCTUnwrap(reopened.bakedMesh).geometry), triangles(expectedBaked))
        XCTAssertEqual(triangles(try XCTUnwrap(reopened.mesh)), triangles(expected))
        value.undo()
        try await settle(value)
        XCTAssertNil(value.errorMessage)
        XCTAssertNil(value.materialIssue)
        XCTAssertEqual(triangles(try XCTUnwrap(value.bakedMesh).geometry), triangles(beforeBaked))
        XCTAssertEqual(value.snapshot?.document.encoded(), source)
        XCTAssertEqual(triangles(try XCTUnwrap(value.mesh)), triangles(before))
        value.redo()
        try await settle(value)
        XCTAssertNil(value.errorMessage)
        XCTAssertNil(value.materialIssue)
        XCTAssertEqual(value.snapshot?.document.encoded(), remainder)
        XCTAssertEqual(triangles(try XCTUnwrap(value.bakedMesh).geometry), triangles(expectedBaked))
        XCTAssertEqual(triangles(try XCTUnwrap(value.mesh)), triangles(expected))
        value.componentDeletionAction(
            ComponentDeletionTarget(
                snapshot: try XCTUnwrap(value.snapshot),
                componentIDs: ["{00000302-0000-4000-8000-000000000302}"]))()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), empty)
        XCTAssertTrue(value.snapshot?.nodes.isEmpty == true)
        XCTAssertTrue(value.snapshot?.parts.isEmpty == true)
        XCTAssertNil(value.mesh)
        XCTAssertNil(value.bakedMesh)
        XCTAssertNil(value.errorMessage)
        XCTAssertNil(value.renderError)
        XCTAssertNil(value.materialIssue)
        value.undo()
        try await settle(value)
        XCTAssertNil(value.errorMessage)
        XCTAssertNil(value.materialIssue)
        XCTAssertEqual(triangles(try XCTUnwrap(value.bakedMesh).geometry), triangles(expectedBaked))
        XCTAssertEqual(value.snapshot?.document.encoded(), remainder)
        XCTAssertEqual(triangles(try XCTUnwrap(value.mesh)), triangles(expected))
    }
}
