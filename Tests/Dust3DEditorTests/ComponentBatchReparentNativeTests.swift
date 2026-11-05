import CryptoKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest
import simd

@testable import Dust3DEditor

// Outside Tests: source/hash review required before compilation or foreign entry.
private enum ReparentAdmission {
    enum Failure: Error {
        case unreviewedInput, timeout, invalidGeometry
        case failedPreview(String)
    }
    static let fixtures: [String: (Int, String, String)] = [
        "anchor": (
            561, "23213dae612f358347a306cbfbc2ee9856f79217061952ac896dbcb7af742b6f",
            "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4NQ0KPGRzMz48bW9kZWwgbmFtZT0nbW9kZWwueG1sJyBvZmZzZXQ9JzAnIHNpemU9JzQ3NicvPjwvZHMzPjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7OGI0MDkwZWEtYTYzYy01YTk2LTk2YTktZjg4Mzg5NzZlZWMyfScgcGFydElkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgeD0nLjInIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezBhMmYwOTRjLTMzNWQtNWJlYi04N2RmLTIyNDM5ZWU3ZWU4Nn0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIGNvbWJpbmVNb2RlPSdOb3JtYWwnIHNtb290aEN1dG9mZkRlZ3JlZXM9JzAnLz48L2NvbXBvbmVudHM+PC9jYW52YXM+"
        ),
        "edited": (
            1411, "b5cfdcb9422b7a2175c3d70d342d34dc5f66e49f284f96e0c69adad034549fb5",
            "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTA5DQo8P3htbCB2ZXJzaW9uPSIxLjAiPz48ZHMzPjxtb2RlbCBuYW1lPSdtb2RlbC54bWwnIG9mZnNldD0nMCcgc2l6ZT0nMTMwMicvPjwvZHMzPjw/eG1sIHZlcnNpb249IjEuMCI/PjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7OGI0MDkwZWEtYTYzYy01YTk2LTk2YTktZjg4Mzg5NzZlZWMyfScgcGFydElkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgeD0nLjInIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48bm9kZSBpZD0nezM2MDkxNWE4LTYxM2MtNTIzYS04MGEzLTNiMzcyZTNjNzdjY30nIHBhcnRJZD0nezM5ZTM5ZWRlLTljZTctNTg4Yi1iZDEyLWYyMjA5NDM5YTg1OX0nIHg9Jy41JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjA1Jy8+PG5vZGUgaWQ9J3tiOGZmODczOC0xNTQ5LTVmZTgtOGM4Ni1kZWUzODVlM2M1NWV9JyBwYXJ0SWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyB4PScuOCcgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4wNScvPjwvbm9kZXM+PGVkZ2VzLz48cGFydHM+PHBhcnQgaWQ9J3swMGJiZDZiNC02MzRlLTVlMjUtOTg4NC01YzQxZjdhYTlkYTF9Jy8+PHBhcnQgaWQ9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9Jy8+PHBhcnQgaWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9Jy8+PC9wYXJ0cz48Y29tcG9uZW50cz48Y29tcG9uZW50IGlkPSd7MGEyZjA5NGMtMzM1ZC01YmViLTg3ZGYtMjI0MzllZTdlZTg2fScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3syMDI3OWMzNC00MDM5LTRkN2MtYmNmZS04ZjQzZjA3Y2U4MWF9JyBjb21iaW5lTW9kZT0nSW52ZXJzaW9uJz48Y29tcG9uZW50IGlkPSd7YzRjNDliMDUtNjY1OC01MTM5LTljOWMtYzljMzg4NWRiNWNkfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MzllMzllZGUtOWNlNy01ODhiLWJkMTItZjIyMDk0MzlhODU5fScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3sxMjI1OGUxMi03YjUyLTVmZGMtOThmZS05Yjk5ZjA5YmFhOWF9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyBjb21iaW5lTW9kZT0nTm9ybWFsJyBzbW9vdGhDdXRvZmZEZWdyZWVzPScwJy8+PC9jb21wb25lbnQ+PC9jb21wb25lbnRzPjwvY2FudmFzPg=="
        ),
        "flat": (
            1276, "16d64591fc0b4879147c746a27e15bc0fa43c426a3e7207af45f89b4a0b4fe87",
            "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4Ng0KPGRzMz48bW9kZWwgbmFtZT0nbW9kZWwueG1sJyBvZmZzZXQ9JzAnIHNpemU9JzExOTAnLz48L2RzMz48Y2FudmFzIG9yaWdpblg9Jy41JyBvcmlnaW5ZPScuNScgb3JpZ2luWj0nLjUnPjxub2Rlcz48bm9kZSBpZD0nezhiNDA5MGVhLWE2M2MtNWE5Ni05NmE5LWY4ODM4OTc2ZWVjMn0nIHBhcnRJZD0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIHg9Jy4yJyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjA1Jy8+PG5vZGUgaWQ9J3szNjA5MTVhOC02MTNjLTUyM2EtODBhMy0zYjM3MmUzYzc3Y2N9JyBwYXJ0SWQ9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9JyB4PScuNScgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4wNScvPjxub2RlIGlkPSd7YjhmZjg3MzgtMTU0OS01ZmU4LThjODYtZGVlMzg1ZTNjNTVlfScgcGFydElkPSd7ZjY4OTQ1MDEtYjRhYy01ZTg0LWFhYmQtZGRkODJhNzVlZDM2fScgeD0nLjgnIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScvPjxwYXJ0IGlkPSd7MzllMzllZGUtOWNlNy01ODhiLWJkMTItZjIyMDk0MzlhODU5fScvPjxwYXJ0IGlkPSd7ZjY4OTQ1MDEtYjRhYy01ZTg0LWFhYmQtZGRkODJhNzVlZDM2fScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezBhMmYwOTRjLTMzNWQtNWJlYi04N2RmLTIyNDM5ZWU3ZWU4Nn0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIGNvbWJpbmVNb2RlPSdOb3JtYWwnIHNtb290aEN1dG9mZkRlZ3JlZXM9JzAnLz48Y29tcG9uZW50IGlkPSd7YzRjNDliMDUtNjY1OC01MTM5LTljOWMtYzljMzg4NWRiNWNkfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MzllMzllZGUtOWNlNy01ODhiLWJkMTItZjIyMDk0MzlhODU5fScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3sxMjI1OGUxMi03YjUyLTVmZGMtOThmZS05Yjk5ZjA5YmFhOWF9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyBjb21iaW5lTW9kZT0nTm9ybWFsJyBzbW9vdGhDdXRvZmZEZWdyZWVzPScwJy8+PC9jb21wb25lbnRzPjwvY2FudmFzPg=="
        ),
        "source": (
            1356, "62e83687679adacb485b1154c47838bc029e01da9ccdf06e83442dff4f3487a0",
            "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4Ng0KPGRzMz48bW9kZWwgbmFtZT0nbW9kZWwueG1sJyBvZmZzZXQ9JzAnIHNpemU9JzEyNzAnLz48L2RzMz48Y2FudmFzIG9yaWdpblg9Jy41JyBvcmlnaW5ZPScuNScgb3JpZ2luWj0nLjUnPjxub2Rlcz48bm9kZSBpZD0nezhiNDA5MGVhLWE2M2MtNWE5Ni05NmE5LWY4ODM4OTc2ZWVjMn0nIHBhcnRJZD0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIHg9Jy4yJyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjA1Jy8+PG5vZGUgaWQ9J3szNjA5MTVhOC02MTNjLTUyM2EtODBhMy0zYjM3MmUzYzc3Y2N9JyBwYXJ0SWQ9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9JyB4PScuNScgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4wNScvPjxub2RlIGlkPSd7YjhmZjg3MzgtMTU0OS01ZmU4LThjODYtZGVlMzg1ZTNjNTVlfScgcGFydElkPSd7ZjY4OTQ1MDEtYjRhYy01ZTg0LWFhYmQtZGRkODJhNzVlZDM2fScgeD0nLjgnIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScvPjxwYXJ0IGlkPSd7MzllMzllZGUtOWNlNy01ODhiLWJkMTItZjIyMDk0MzlhODU5fScvPjxwYXJ0IGlkPSd7ZjY4OTQ1MDEtYjRhYy01ZTg0LWFhYmQtZGRkODJhNzVlZDM2fScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezBhMmYwOTRjLTMzNWQtNWJlYi04N2RmLTIyNDM5ZWU3ZWU4Nn0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIGNvbWJpbmVNb2RlPSdOb3JtYWwnIHNtb290aEN1dG9mZkRlZ3JlZXM9JzAnLz48Y29tcG9uZW50IGlkPSd7YzRjNDliMDUtNjY1OC01MTM5LTljOWMtYzljMzg4NWRiNWNkfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MzllMzllZGUtOWNlNy01ODhiLWJkMTItZjIyMDk0MzlhODU5fScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3sxMjI1OGUxMi03YjUyLTVmZGMtOThmZS05Yjk5ZjA5YmFhOWF9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyBjb21iaW5lTW9kZT0nTm9ybWFsJyBzbW9vdGhDdXRvZmZEZWdyZWVzPScwJy8+PGNvbXBvbmVudCBpZD0nezIwMjc5YzM0LTQwMzktNGQ3Yy1iY2ZlLThmNDNmMDdjZTgxYX0nIGNvbWJpbmVNb2RlPSdJbnZlcnNpb24nLz48L2NvbXBvbmVudHM+PC9jYW52YXM+"
        ),
    ]
    static func check(_ data: Data) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard fixtures.values.contains(where: { $0.0 == data.count && $0.1 == digest }) else {
            throw Failure.unreviewedInput
        }
    }
    static func data(_ name: String) throws -> Data {
        guard let value = fixtures[name], let data = Data(base64Encoded: value.2) else {
            throw Failure.unreviewedInput
        }
        try check(data)
        return data
    }
}
private struct ReviewedReparentPreview: EditorPreviewServing {
    let service = EditorPreviewService()
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        try ReparentAdmission.check(data)
        return try await service.generate(data, scopeID: scopeID)
    }
    func reset(scopeID: UUID) async throws { try await service.reset(scopeID: scopeID) }
}
private struct BlockedReparentNative: ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws
        -> MeshWithBakedTextures
    { throw CancellationError() }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits)
        async throws -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws
        -> ImportedMaterialRenderData?
    { nil }
}
@MainActor final class ComponentBatchReparentNativeTests: XCTestCase {
    private let destination = "{20279c34-4039-4d7c-bcfe-8f43f07ce81a}"
    private let owners = [
        "{c4c49b05-6658-5139-9c9c-c9c3885db5cd}",
        "{12258e12-7b52-5fdc-98fe-9b99f09baa9a}",
    ]
    private struct Point: Hashable, Comparable {
        let x: UInt32
        let y: UInt32
        let z: UInt32
        init(_ p: SIMD3<Float>) {
            x = p.x.bitPattern
            y = p.y.bitPattern
            z = p.z.bitPattern
        }
        static func < (a: Self, b: Self) -> Bool {
            [a.x, a.y, a.z].lexicographicallyPrecedes([b.x, b.y, b.z])
        }
    }
    private struct Triangle: Hashable {
        let points: [Point]
        init(_ points: [Point]) {
            self.points =
                (0..<3).map { offset in (0..<3).map { points[($0 + offset) % 3] } }
                .sorted { $0.lexicographicallyPrecedes($1) }[0]
        }
    }
    private func triangleCounts(_ mesh: IndexedMesh) throws -> [Triangle: Int] {
        guard !mesh.indices.isEmpty, mesh.indices.count % 3 == 0,
            mesh.indices.allSatisfy({ Int($0) < mesh.vertices.count })
        else { throw ReparentAdmission.Failure.invalidGeometry }
        var result: [Triangle: Int] = [:]
        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let points = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])].position }
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
                Set(points.map(Point.init)).count == 3,
                simd_length(simd_cross(points[1] - points[0], points[2] - points[0])) > 0
            else { throw ReparentAdmission.Failure.invalidGeometry }
            result[Triangle(points.map(Point.init)), default: 0] += 1
        }
        return result
    }
    private func store() -> EditorStore {
        let blocked = BlockedReparentNative()
        return EditorStore(
            preview: ReviewedReparentPreview(), materialBaker: blocked,
            importedMaterialLoader: blocked, sourceMaterialBaker: blocked, animationCatalog: blocked)
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<3000 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ReparentAdmission.Failure.timeout
    }
    private func currentMesh(_ store: EditorStore) throws -> IndexedMesh {
        guard store.errorMessage == nil, store.previewState.errorMessage == nil,
            !store.previewState.isStale
        else {
            throw ReparentAdmission.Failure.failedPreview(
                store.errorMessage ?? store.previewState.errorMessage ?? "Preview is stale")
        }
        return try XCTUnwrap(store.mesh)
    }
    func testBatchReparentMatchesIndependentGeometryAcrossUndoRedoAndReopen() async throws {
        let source = try ReparentAdmission.data("source")
        let flat = try ReparentAdmission.data("flat")
        let expectedEdited = try ReparentAdmission.data("edited")
        let document = try Dust3DDocument(data: source)
        let predicted = try document.applying(.reparentComponents(ids: Array(owners.reversed()), parentID: destination))
        guard predicted.encoded() == expectedEdited else { throw ReparentAdmission.Failure.unreviewedInput }

        let preview = ReviewedReparentPreview()
        let reference = try await preview.generate(flat, scopeID: UUID())
        let anchor = try await preview.generate(ReparentAdmission.data("anchor"), scopeID: UUID())
        let flatMesh = try XCTUnwrap(reference.output?.mesh)
        let anchorMesh = try XCTUnwrap(anchor.output?.mesh)
        XCTAssertEqual(flatMesh.triangleCount, 48)
        XCTAssertEqual(anchorMesh.triangleCount, 16)
        let flatTriangles = try triangleCounts(flatMesh)
        let anchorTriangles = try triangleCounts(anchorMesh)

        let store = store()
        defer { store.stop() }
        await store.load(data: source)
        try await settle(store)
        XCTAssertEqual(try triangleCounts(currentMesh(store)), flatTriangles)
        store.selectComponents(Set(owners))
        try await settle(store)
        let original = try XCTUnwrap(store.snapshot)
        let target = try XCTUnwrap(ComponentBatchReparentTarget(snapshot: original))
        let camera = store.cameraReset
        var completed = false
        store.reparentComponents(to: .component(destination), target: target) { completed = $0 }
        try await settle(store)
        let edited = try XCTUnwrap(store.snapshot)
        guard completed, edited.document.encoded() == expectedEdited else {
            throw ReparentAdmission.Failure.unreviewedInput
        }
        XCTAssertEqual(edited.nodes, original.nodes)
        XCTAssertEqual(edited.parts, original.parts)
        XCTAssertEqual(edited.edges, original.edges)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(edited.selectedComponentIDs, Set(owners))
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(try triangleCounts(currentMesh(store)), anchorTriangles)

        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(try triangleCounts(currentMesh(store)), flatTriangles)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), expectedEdited)
        XCTAssertEqual(try triangleCounts(currentMesh(store)), anchorTriangles)

        let reopened = self.store()
        defer { reopened.stop() }
        await reopened.load(data: edited.document.encoded())
        try await settle(reopened)
        XCTAssertEqual(reopened.snapshot?.document.encoded(), expectedEdited)
        XCTAssertFalse(reopened.canUndo)
        XCTAssertEqual(try triangleCounts(currentMesh(reopened)), anchorTriangles)
    }
}
