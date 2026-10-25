import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

private actor CopiedFallbackBackend: EditorMeshGenerating {
    let source: MeshLoadingError
    let geometry: Result<MeshGenerationResult, MeshLoadingError>
    private(set) var fallbackCalls = 0

    init(source: MeshLoadingError, geometry: Result<MeshGenerationResult, MeshLoadingError>) {
        self.source = source
        self.geometry = geometry
    }

    func generateSourcedIndexed(data: Data, maximumPayloadBytes: Int, maximumSourcePayloadBytes: Int)
        async throws -> SourcedMeshGenerationResult
    {
        throw source
    }

    func generateIndexed(data: Data, maximumPayloadBytes: Int) async throws -> MeshGenerationResult {
        fallbackCalls += 1
        return try geometry.get()
    }

    func reset() {}
}

@MainActor
final class EditorPreviewFallbackContractTests: XCTestCase {
    private func copiedGeometry() -> MeshGenerationResult {
        let vertex = MeshVertex(
            position: .zero, normal: SIMD3(0, 1, 0), color: SIMD4(1, 1, 1, 1))
        return MeshGenerationResult(
            mesh: IndexedMesh(
                vertices: [vertex], indices: [0, 0, 0], nodeCount: 1, partCount: 1, warning: "copied fixture"),
            statistics: MeshGenerationStatistics(native: Dust3DGenerationStats()))
    }

    func testOptionalSourceFailurePreservesCopiedGeometryAndOriginalDiagnostic() async throws {
        for status: UInt32 in [3, 4] {
            let source = MeshLoadingError(status: status, message: "source detail \(status)")
            let backend = CopiedFallbackBackend(source: source, geometry: .success(copiedGeometry()))
            let service = EditorPreviewService(makeSession: { _ in backend })
            let result = try await service.generate(Data(), scopeID: UUID())
            XCTAssertEqual(result.mesh?.indices, [0, 0, 0])
            XCTAssertEqual(result.mesh?.warning, "copied fixture")
            XCTAssertNil(result.output?.sourceHints)
            XCTAssertEqual(result.sourceIssue?.status, source.status)
            XCTAssertEqual(result.sourceIssue?.message, source.message)
            let calls = await backend.fallbackCalls
            XCTAssertEqual(calls, 1)
        }
    }

    func testFallbackFailurePreservesBothCausesWithoutDuplicatingEqualMessages() async throws {
        for message in ["geometry detail", "source detail"] {
            let source = MeshLoadingError(status: 3, message: "source detail")
            let backend = CopiedFallbackBackend(
                source: source, geometry: .failure(MeshLoadingError(status: 2, message: message)))
            let service = EditorPreviewService(makeSession: { _ in backend })
            do {
                _ = try await service.generate(Data(), scopeID: UUID())
                XCTFail("Both failed preview attempts must fail the request")
            } catch let error as EditorPreviewFallbackError {
                XCTAssertEqual(error.source.message, source.message)
                XCTAssertEqual(error.geometryMessage, message)
                XCTAssertEqual(
                    error.localizedDescription,
                    message == source.message ? message : "\(message)\nSource details: \(source.message)")
            }
        }
    }

    func testOtherSourceErrorsPropagateWithoutAttemptingFallback() async throws {
        let source = MeshLoadingError(status: 2, message: "original archive diagnostic")
        let backend = CopiedFallbackBackend(source: source, geometry: .success(copiedGeometry()))
        let service = EditorPreviewService(makeSession: { _ in backend })
        do {
            _ = try await service.generate(Data(), scopeID: UUID())
            XCTFail("Nonoptional source failure must propagate")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, source.status)
            XCTAssertEqual(error.message, source.message)
        }
        let calls = await backend.fallbackCalls
        XCTAssertEqual(calls, 0)
    }
}
