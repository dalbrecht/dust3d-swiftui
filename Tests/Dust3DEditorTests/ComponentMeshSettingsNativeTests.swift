import CryptoKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest
import simd

@testable import Dust3DEditor

// Outside Tests: source/hash review required before compilation or foreign entry.
private enum MeshSettingsAdmission {
    enum Failure: Error {
        case unreviewedInput, timeout, invalidGeometry
        case failedPreview(String)
    }
    static let fixtures: [String: (Int, String, String)] = [
        "source": (
            1276, "16d64591fc0b4879147c746a27e15bc0fa43c426a3e7207af45f89b4a0b4fe87",
            "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4Ng0KPGRzMz48bW9kZWwgbmFtZT0nbW9kZWwueG1sJyBvZmZzZXQ9JzAnIHNpemU9JzExOTAnLz48L2RzMz48Y2FudmFzIG9yaWdpblg9Jy41JyBvcmlnaW5ZPScuNScgb3JpZ2luWj0nLjUnPjxub2Rlcz48bm9kZSBpZD0nezhiNDA5MGVhLWE2M2MtNWE5Ni05NmE5LWY4ODM4OTc2ZWVjMn0nIHBhcnRJZD0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIHg9Jy4yJyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjA1Jy8+PG5vZGUgaWQ9J3szNjA5MTVhOC02MTNjLTUyM2EtODBhMy0zYjM3MmUzYzc3Y2N9JyBwYXJ0SWQ9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9JyB4PScuNScgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4wNScvPjxub2RlIGlkPSd7YjhmZjg3MzgtMTU0OS01ZmU4LThjODYtZGVlMzg1ZTNjNTVlfScgcGFydElkPSd7ZjY4OTQ1MDEtYjRhYy01ZTg0LWFhYmQtZGRkODJhNzVlZDM2fScgeD0nLjgnIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScvPjxwYXJ0IGlkPSd7MzllMzllZGUtOWNlNy01ODhiLWJkMTItZjIyMDk0MzlhODU5fScvPjxwYXJ0IGlkPSd7ZjY4OTQ1MDEtYjRhYy01ZTg0LWFhYmQtZGRkODJhNzVlZDM2fScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezBhMmYwOTRjLTMzNWQtNWJlYi04N2RmLTIyNDM5ZWU3ZWU4Nn0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIGNvbWJpbmVNb2RlPSdOb3JtYWwnIHNtb290aEN1dG9mZkRlZ3JlZXM9JzAnLz48Y29tcG9uZW50IGlkPSd7YzRjNDliMDUtNjY1OC01MTM5LTljOWMtYzljMzg4NWRiNWNkfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MzllMzllZGUtOWNlNy01ODhiLWJkMTItZjIyMDk0MzlhODU5fScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3sxMjI1OGUxMi03YjUyLTVmZGMtOThmZS05Yjk5ZjA5YmFhOWF9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyBjb21iaW5lTW9kZT0nTm9ybWFsJyBzbW9vdGhDdXRvZmZEZWdyZWVzPScwJy8+PC9jb21wb25lbnRzPjwvY2FudmFzPg=="
        ),
        "inversion": (
            1326, "e398b4f9f7a6109bcb3a6de007216ab9febe4a558746ce4b35909f5ce95f72e2",
            "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTA5DQo8P3htbCB2ZXJzaW9uPSIxLjAiPz48ZHMzPjxtb2RlbCBuYW1lPSdtb2RlbC54bWwnIG9mZnNldD0nMCcgc2l6ZT0nMTIxNycvPjwvZHMzPjw/eG1sIHZlcnNpb249IjEuMCI/PjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7OGI0MDkwZWEtYTYzYy01YTk2LTk2YTktZjg4Mzg5NzZlZWMyfScgcGFydElkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgeD0nLjInIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48bm9kZSBpZD0nezM2MDkxNWE4LTYxM2MtNTIzYS04MGEzLTNiMzcyZTNjNzdjY30nIHBhcnRJZD0nezM5ZTM5ZWRlLTljZTctNTg4Yi1iZDEyLWYyMjA5NDM5YTg1OX0nIHg9Jy41JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjA1Jy8+PG5vZGUgaWQ9J3tiOGZmODczOC0xNTQ5LTVmZTgtOGM4Ni1kZWUzODVlM2M1NWV9JyBwYXJ0SWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyB4PScuOCcgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4wNScvPjwvbm9kZXM+PGVkZ2VzLz48cGFydHM+PHBhcnQgaWQ9J3swMGJiZDZiNC02MzRlLTVlMjUtOTg4NC01YzQxZjdhYTlkYTF9Jy8+PHBhcnQgaWQ9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9Jy8+PHBhcnQgaWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9Jy8+PC9wYXJ0cz48Y29tcG9uZW50cz48Y29tcG9uZW50IGlkPSd7MGEyZjA5NGMtMzM1ZC01YmViLTg3ZGYtMjI0MzllZTdlZTg2fScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3tjNGM0OWIwNS02NjU4LTUxMzktOWM5Yy1jOWMzODg1ZGI1Y2R9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9JyBzbW9vdGhDdXRvZmZEZWdyZWVzPScwJyBjb21iaW5lTW9kZT0nSW52ZXJzaW9uJy8+PGNvbXBvbmVudCBpZD0nezEyMjU4ZTEyLTdiNTItNWZkYy05OGZlLTliOTlmMDliYWE5YX0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0ne2Y2ODk0NTAxLWI0YWMtNWU4NC1hYWJkLWRkZDgyYTc1ZWQzNn0nIHNtb290aEN1dG9mZkRlZ3JlZXM9JzAnIGNvbWJpbmVNb2RlPSdJbnZlcnNpb24nLz48L2NvbXBvbmVudHM+PC9jYW52YXM+"
        ),
        "uncombined": (
            1328, "5796646778d1f9a84ab38bb6c0021399f406434653a5baa55bae9d6a6cec92e8",
            "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTA5DQo8P3htbCB2ZXJzaW9uPSIxLjAiPz48ZHMzPjxtb2RlbCBuYW1lPSdtb2RlbC54bWwnIG9mZnNldD0nMCcgc2l6ZT0nMTIxOScvPjwvZHMzPjw/eG1sIHZlcnNpb249IjEuMCI/PjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7OGI0MDkwZWEtYTYzYy01YTk2LTk2YTktZjg4Mzg5NzZlZWMyfScgcGFydElkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgeD0nLjInIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48bm9kZSBpZD0nezM2MDkxNWE4LTYxM2MtNTIzYS04MGEzLTNiMzcyZTNjNzdjY30nIHBhcnRJZD0nezM5ZTM5ZWRlLTljZTctNTg4Yi1iZDEyLWYyMjA5NDM5YTg1OX0nIHg9Jy41JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjA1Jy8+PG5vZGUgaWQ9J3tiOGZmODczOC0xNTQ5LTVmZTgtOGM4Ni1kZWUzODVlM2M1NWV9JyBwYXJ0SWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyB4PScuOCcgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4wNScvPjwvbm9kZXM+PGVkZ2VzLz48cGFydHM+PHBhcnQgaWQ9J3swMGJiZDZiNC02MzRlLTVlMjUtOTg4NC01YzQxZjdhYTlkYTF9Jy8+PHBhcnQgaWQ9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9Jy8+PHBhcnQgaWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9Jy8+PC9wYXJ0cz48Y29tcG9uZW50cz48Y29tcG9uZW50IGlkPSd7MGEyZjA5NGMtMzM1ZC01YmViLTg3ZGYtMjI0MzllZTdlZTg2fScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3tjNGM0OWIwNS02NjU4LTUxMzktOWM5Yy1jOWMzODg1ZGI1Y2R9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9JyBzbW9vdGhDdXRvZmZEZWdyZWVzPScwJyBjb21iaW5lTW9kZT0nVW5jb21iaW5lZCcvPjxjb21wb25lbnQgaWQ9J3sxMjI1OGUxMi03YjUyLTVmZGMtOThmZS05Yjk5ZjA5YmFhOWF9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyBzbW9vdGhDdXRvZmZEZWdyZWVzPScwJyBjb21iaW5lTW9kZT0nVW5jb21iaW5lZCcvPjwvY29tcG9uZW50cz48L2NhbnZhcz4="
        ),
        "smooth": (
            1328, "b982cf07603cdbeb9dd6642f5029657e15d59bd7143ae8743c601139d5b66a55",
            "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTA5DQo8P3htbCB2ZXJzaW9uPSIxLjAiPz48ZHMzPjxtb2RlbCBuYW1lPSdtb2RlbC54bWwnIG9mZnNldD0nMCcgc2l6ZT0nMTIxOScvPjwvZHMzPjw/eG1sIHZlcnNpb249IjEuMCI/PjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7OGI0MDkwZWEtYTYzYy01YTk2LTk2YTktZjg4Mzg5NzZlZWMyfScgcGFydElkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgeD0nLjInIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48bm9kZSBpZD0nezM2MDkxNWE4LTYxM2MtNTIzYS04MGEzLTNiMzcyZTNjNzdjY30nIHBhcnRJZD0nezM5ZTM5ZWRlLTljZTctNTg4Yi1iZDEyLWYyMjA5NDM5YTg1OX0nIHg9Jy41JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjA1Jy8+PG5vZGUgaWQ9J3tiOGZmODczOC0xNTQ5LTVmZTgtOGM4Ni1kZWUzODVlM2M1NWV9JyBwYXJ0SWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyB4PScuOCcgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4wNScvPjwvbm9kZXM+PGVkZ2VzLz48cGFydHM+PHBhcnQgaWQ9J3swMGJiZDZiNC02MzRlLTVlMjUtOTg4NC01YzQxZjdhYTlkYTF9Jy8+PHBhcnQgaWQ9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9Jy8+PHBhcnQgaWQ9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9Jy8+PC9wYXJ0cz48Y29tcG9uZW50cz48Y29tcG9uZW50IGlkPSd7MGEyZjA5NGMtMzM1ZC01YmViLTg3ZGYtMjI0MzllZTdlZTg2fScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgY29tYmluZU1vZGU9J05vcm1hbCcgc21vb3RoQ3V0b2ZmRGVncmVlcz0nMCcvPjxjb21wb25lbnQgaWQ9J3tjNGM0OWIwNS02NjU4LTUxMzktOWM5Yy1jOWMzODg1ZGI1Y2R9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3szOWUzOWVkZS05Y2U3LTU4OGItYmQxMi1mMjIwOTQzOWE4NTl9JyBjb21iaW5lTW9kZT0nTm9ybWFsJyBzbW9vdGhDdXRvZmZEZWdyZWVzPScxODAuMCcvPjxjb21wb25lbnQgaWQ9J3sxMjI1OGUxMi03YjUyLTVmZGMtOThmZS05Yjk5ZjA5YmFhOWF9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3tmNjg5NDUwMS1iNGFjLTVlODQtYWFiZC1kZGQ4MmE3NWVkMzZ9JyBjb21iaW5lTW9kZT0nTm9ybWFsJyBzbW9vdGhDdXRvZmZEZWdyZWVzPScxODAuMCcvPjwvY29tcG9uZW50cz48L2NhbnZhcz4="
        ),
        "independent-anchor": (
            561, "23213dae612f358347a306cbfbc2ee9856f79217061952ac896dbcb7af742b6f",
            "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4NQ0KPGRzMz48bW9kZWwgbmFtZT0nbW9kZWwueG1sJyBvZmZzZXQ9JzAnIHNpemU9JzQ3NicvPjwvZHMzPjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7OGI0MDkwZWEtYTYzYy01YTk2LTk2YTktZjg4Mzg5NzZlZWMyfScgcGFydElkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScgeD0nLjInIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMDUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDBiYmQ2YjQtNjM0ZS01ZTI1LTk4ODQtNWM0MWY3YWE5ZGExfScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezBhMmYwOTRjLTMzNWQtNWJlYi04N2RmLTIyNDM5ZWU3ZWU4Nn0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0nezAwYmJkNmI0LTYzNGUtNWUyNS05ODg0LTVjNDFmN2FhOWRhMX0nIGNvbWJpbmVNb2RlPSdOb3JtYWwnIHNtb290aEN1dG9mZkRlZ3JlZXM9JzAnLz48L2NvbXBvbmVudHM+PC9jYW52YXM+"
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
private struct ReviewedMeshSettingsPreview: EditorPreviewServing {
    let service = EditorPreviewService()
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        try MeshSettingsAdmission.check(data)
        return try await service.generate(data, scopeID: scopeID)
    }
    func reset(scopeID: UUID) async throws { try await service.reset(scopeID: scopeID) }
}
private struct BlockedMeshSettingsNative: ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
@MainActor final class ComponentMeshSettingsNativeTests: XCTestCase {
    private let owners: Set<String> = [
        "{c4c49b05-6658-5139-9c9c-c9c3885db5cd}", "{12258e12-7b52-5fdc-98fe-9b99f09baa9a}",
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
    private struct Face {
        let key: Triangle
        let points: [Point]
        let normal: SIMD3<Double>
        let weights: [Double]
    }
    private func vector(_ p: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3(Double(p.x), Double(p.y), Double(p.z))
    }
    private func region(_ p: SIMD3<Float>) -> Int { p.x < -0.15 ? 0 : (p.x < 0.15 ? 1 : 2) }
    private func faces(_ mesh: IndexedMesh) throws -> [Face] {
        guard !mesh.indices.isEmpty, mesh.indices.count % 3 == 0,
            mesh.indices.allSatisfy({ Int($0) < mesh.vertices.count }),
            mesh.vertices.allSatisfy({
                let p = $0.position
                return p.x.isFinite && p.y.isFinite && p.z.isFinite && abs(p.x) < 1 && abs(p.y) < 1
                    && abs(p.z) < 1
            })
        else { throw MeshSettingsAdmission.Failure.invalidGeometry }
        var result: [Face] = []
        var unique = Set<[Point]>()
        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let vertices = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])] }
            let p = vertices.map { vector($0.position) }
            let keys = vertices.map { Point($0.position) }
            // No coincident duplicate faces are expected in this audited disjoint manifold family.
            // Reject rather than deduplicate: every occurrence must otherwise contribute its weight.
            guard unique.insert(keys.sorted()).inserted, Set(keys).count == 3,
                Set(vertices.map { region($0.position) }).count == 1
            else { throw MeshSettingsAdmission.Failure.invalidGeometry }
            let cross = simd_cross(p[1] - p[0], p[2] - p[0])
            let length = simd_length(cross)
            guard length.isFinite && length > 0 else {
                throw MeshSettingsAdmission.Failure.invalidGeometry
            }
            let weights = (0..<3).map { i -> Double in
                let a = p[(i + 1) % 3] - p[i]
                let b = p[(i + 2) % 3] - p[i]
                let cosine = max(-1, min(1, simd_dot(a, b) / (simd_length(a) * simd_length(b))))
                // Radians vs degrees and half-area vs cross magnitude differ only by global factors,
                // which cancel when the incident weighted vector is normalized.
                return acos(cosine) * (length / 2)
            }
            result.append(
                Face(key: Triangle(keys), points: keys, normal: cross / length, weights: weights))
        }
        return result
    }
    private func triangleCounts(_ mesh: IndexedMesh) throws -> [Triangle: Int] {
        var result: [Triangle: Int] = [:]
        for face in try faces(mesh) { result[face.key, default: 0] += 1 }
        return result
    }
    private func normalOracle(_ baseline: [Face]) throws -> [Point: SIMD3<Double>] {
        var incidents: [Point: [Int]] = [:]
        var sums: [Point: SIMD3<Double>] = [:]
        for (index, face) in baseline.enumerated() {
            for corner in 0..<3 {
                incidents[face.points[corner], default: []].append(index)
                sums[face.points[corner], default: .zero] += face.normal * face.weights[corner]
            }
        }
        for (point, incident) in incidents {
            // The core uses original vertex-index adjacency. Position grouping is valid only for this
            // regular, noncoincident manifold fixture; ensure the incident face fan is connected.
            var pending = [incident[0]]
            var visited = Set<Int>()
            while let current = pending.popLast() {
                guard visited.insert(current).inserted else { continue }
                for other in incident where !visited.contains(other) {
                    let shared = Set(baseline[current].points).intersection(baseline[other].points)
                    if shared.count == 2 && shared.contains(point) { pending.append(other) }
                }
            }
            guard visited.count == incident.count else {
                throw MeshSettingsAdmission.Failure.invalidGeometry
            }
        }
        return try sums.mapValues { sum in
            let length = simd_length(sum)
            guard length.isFinite && length > 0 else {
                throw MeshSettingsAdmission.Failure.invalidGeometry
            }
            return sum / length
        }
    }
    private func assertNormal(
        _ actual: SIMD3<Float>, _ expected: SIMD3<Double>, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let p = vector(actual)
        XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite, file: file, line: line)
        XCTAssertEqual(simd_length(p), 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(p.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(p.y, expected.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(p.z, expected.z, accuracy: 0.0001, file: file, line: line)
    }
    private func store() -> EditorStore {
        let blocked = BlockedMeshSettingsNative()
        return EditorStore(
            preview: ReviewedMeshSettingsPreview(), materialBaker: blocked,
            importedMaterialLoader: blocked, sourceMaterialBaker: blocked, animationCatalog: blocked)
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<3000 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw MeshSettingsAdmission.Failure.timeout
    }
    private func currentMesh(_ store: EditorStore) throws -> IndexedMesh {
        guard store.errorMessage == nil, store.previewState.errorMessage == nil,
            !store.previewState.isStale
        else {
            throw MeshSettingsAdmission.Failure.failedPreview(
                store.errorMessage ?? store.previewState.errorMessage ?? "Preview is stale")
        }
        return try XCTUnwrap(store.mesh)
    }
    func testActualBatchModesAndIndependentCornerNormalsPreserveHistoryAndReopen() async throws {
        let source = try MeshSettingsAdmission.data("source")
        let store = store()
        defer { store.stop() }
        await store.load(data: source)
        try await settle(store)
        store.selectComponents(owners)
        try await settle(store)
        let original = try XCTUnwrap(store.snapshot)
        let baseline = try currentMesh(store)
        let baselineFaces = try faces(baseline)
        XCTAssertEqual(baseline.triangleCount, 48)
        let baselineByTriangle = Dictionary(uniqueKeysWithValues: baselineFaces.map { ($0.key, $0) })
        for start in stride(from: 0, to: baseline.indices.count, by: 3) {
            let face = baselineFaces[start / 3]
            for corner in 0..<3 {
                assertNormal(baseline.vertices[Int(baseline.indices[start + corner])].normal, face.normal)
            }
        }
        let expectedNormals = try normalOracle(baselineFaces)
        let camera = store.cameraReset
        store.componentMeshAction(.combineMode(.inversion), target: .init(snapshot: original))()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), try MeshSettingsAdmission.data("inversion"))
        XCTAssertEqual(store.snapshot?.nodes, original.nodes)
        XCTAssertEqual(store.snapshot?.parts, original.parts)
        let inverted = try currentMesh(store)
        XCTAssertEqual(inverted.triangleCount, 16)
        let comparison = try await ReviewedMeshSettingsPreview().generate(
            MeshSettingsAdmission.data("independent-anchor"), scopeID: UUID())
        let anchor = try XCTUnwrap(comparison.output?.mesh)
        XCTAssertEqual(try triangleCounts(inverted), try triangleCounts(anchor))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(try triangleCounts(currentMesh(store)), try triangleCounts(baseline))
        store.redo()
        try await settle(store)
        XCTAssertEqual(try triangleCounts(currentMesh(store)), try triangleCounts(anchor))
        store.undo()
        try await settle(store)
        store.componentMeshAction(
            .combineMode(.uncombined), target: .init(snapshot: try XCTUnwrap(store.snapshot)))()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), try MeshSettingsAdmission.data("uncombined"))
        XCTAssertEqual(try triangleCounts(currentMesh(store)), try triangleCounts(baseline))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        store.componentMeshAction(
            .smoothCutoffDegrees(180), target: .init(snapshot: try XCTUnwrap(store.snapshot)))()
        try await settle(store)
        let smooth = try currentMesh(store)
        let saved = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(saved, try MeshSettingsAdmission.data("smooth"))
        XCTAssertEqual(store.snapshot?.nodes, original.nodes)
        XCTAssertEqual(store.snapshot?.parts, original.parts)
        XCTAssertEqual(try triangleCounts(smooth), try triangleCounts(baseline))
        func assertSmooth(_ mesh: IndexedMesh) throws -> [Int] {
            var changed = [0, 0, 0]
            for start in stride(from: 0, to: mesh.indices.count, by: 3) {
                let vertices = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])] }
                let face = try XCTUnwrap(baselineByTriangle[Triangle(vertices.map { Point($0.position) })])
                for vertex in vertices {
                    let owner = region(vertex.position)
                    let expected: SIMD3<Double>
                    if owner == 0 {
                        expected = face.normal
                    } else {
                        expected = try XCTUnwrap(expectedNormals[Point(vertex.position)])
                    }
                    assertNormal(vertex.normal, expected)
                    if simd_length(expected - face.normal) > 0.01 { changed[owner] += 1 }
                }
            }
            return changed
        }
        let changed = try assertSmooth(smooth)
        XCTAssertEqual(changed[0], 0)
        XCTAssertGreaterThan(changed[1], 0)
        XCTAssertGreaterThan(changed[2], 0)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, owners)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertEqual(try triangleCounts(currentMesh(store)), try triangleCounts(baseline))
        XCTAssertFalse(store.canUndo)
        let flatAgain = try currentMesh(store)
        for start in stride(from: 0, to: flatAgain.indices.count, by: 3) {
            let vertices = (0..<3).map { flatAgain.vertices[Int(flatAgain.indices[start + $0])] }
            let face = try XCTUnwrap(baselineByTriangle[Triangle(vertices.map { Point($0.position) })])
            for vertex in vertices { assertNormal(vertex.normal, face.normal) }
        }
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        _ = try assertSmooth(currentMesh(store))
        await store.load(data: saved)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
        XCTAssertEqual(store.snapshot?.nodes, original.nodes)
        XCTAssertEqual(store.snapshot?.parts, original.parts)
        _ = try assertSmooth(currentMesh(store))
        print(
            "Batch mesh geometry48→16→48; independently weighted normal changes per owner=\(changed), preview only; no material/GPU proof"
        )
    }
}
