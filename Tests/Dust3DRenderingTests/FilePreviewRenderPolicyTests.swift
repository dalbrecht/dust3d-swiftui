import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class FilePreviewRenderPolicyTests: XCTestCase {
    func testPreservesSuccessfulMaterialRenderingIncludingFullyTransparentImages() async throws {
        let baked = try BakedMetalFixture.quad()
        let transparent = try image(alpha: 0)
        for materials in [
            MeshMaterialContent.baked(baked), .sourceBaked(BakedMetalFixture.source(baked, policy: nil)),
            .imported(try importedRenderFixture()),
        ] {
            var calls: [String] = []
            let result = try await FilePreviewRenderPolicy.render(
                document: document(materials: materials),
                renderMaterials: { _ in
                    calls.append("materials")
                    return transparent
                },
                renderGeometry: { _ in
                    calls.append("geometry")
                    throw PreviewRenderFailure.unexpected
                })
            XCTAssertEqual(calls, ["materials"])
            XCTAssertEqual(result.image.pixels, transparent.pixels)
            XCTAssertNil(result.materialError)
        }
    }

    func testCarriesOriginalPreparationCauseWithOrdinaryGeometry() async throws {
        let expected = try image()
        var calls: [String] = []
        let result = try await FilePreviewRenderPolicy.render(
            document: document(materials: nil, materialError: PreviewRenderFailure.preparation),
            renderMaterials: { _ in throw PreviewRenderFailure.unexpected },
            renderGeometry: { mesh in
                calls.append("geometry")
                XCTAssertEqual(mesh.triangleCount, 2)
                return expected
            })
        XCTAssertEqual(calls, ["geometry"])
        XCTAssertEqual(result.image.pixels, expected.pixels)
        XCTAssertEqual(result.materialError as? PreviewRenderFailure, .preparation)
    }

    func testFallsBackAfterMaterialRenderingFailureAndRetainsItsCause() async throws {
        let expected = try image()
        var calls: [String] = []
        let result = try await FilePreviewRenderPolicy.render(
            document: document(materials: .baked(try BakedMetalFixture.quad())),
            renderMaterials: { _ in
                calls.append("materials")
                throw PreviewRenderFailure.material
            },
            renderGeometry: { _ in
                calls.append("geometry")
                return expected
            })
        XCTAssertEqual(calls, ["materials", "geometry"])
        XCTAssertEqual(result.image.pixels, expected.pixels)
        XCTAssertEqual(result.materialError as? PreviewRenderFailure, .material)
    }

    func testSurfacesBothOriginalCausesWhenGeometryFallbackAlsoFails() async throws {
        do {
            _ = try await FilePreviewRenderPolicy.render(
                document: document(materials: .baked(try BakedMetalFixture.quad())),
                renderMaterials: { _ in throw PreviewRenderFailure.material },
                renderGeometry: { _ in throw PreviewRenderFailure.geometry })
            XCTFail("Both failures must be retained")
        } catch let error as FilePreviewRenderingError {
            guard case .geometryFallbackFailed(let material, let geometry) = error else {
                return XCTFail("Expected paired failure causes")
            }
            XCTAssertEqual(material as? PreviewRenderFailure, .material)
            XCTAssertEqual(geometry as? PreviewRenderFailure, .geometry)
            XCTAssertTrue(error.localizedDescription.contains("original material cause"))
            XCTAssertTrue(error.localizedDescription.contains("original geometry cause"))
        }
        do {
            _ = try await FilePreviewRenderPolicy.render(
                document: document(materials: nil),
                renderMaterials: { _ in throw PreviewRenderFailure.unexpected },
                renderGeometry: { _ in throw PreviewRenderFailure.geometry })
            XCTFail("Geometry-only failure must propagate")
        } catch { XCTAssertEqual(error as? PreviewRenderFailure, .geometry) }
    }

    func testCancellationCannotStartFallbackWorkOrPublishAnyImage() async throws {
        let expected = try image()
        let baked = try BakedMetalFixture.quad()
        for phase in CancellationPhase.allCases {
            var calls: [String] = []
            let input = try document(materials: phase == .geometryOnly ? nil : .baked(baked))
            let task = Task {
                if phase == .before { withUnsafeCurrentTask { $0?.cancel() } }
                return try await FilePreviewRenderPolicy.render(
                    document: input,
                    renderMaterials: { _ in
                        calls.append("materials")
                        if phase == .materials { throw CancellationError() }
                        if phase == .materialResult {
                            withUnsafeCurrentTask { $0?.cancel() }
                            return expected
                        }
                        if phase == .cancelledFailure { withUnsafeCurrentTask { $0?.cancel() } }
                        throw PreviewRenderFailure.material
                    },
                    renderGeometry: { _ in
                        calls.append("geometry")
                        if phase == .fallback { throw CancellationError() }
                        withUnsafeCurrentTask { $0?.cancel() }
                        return expected
                    })
            }
            do {
                _ = try await task.value
                XCTFail("Cancelled work published at \(phase)")
            } catch is CancellationError {}
            switch phase {
            case .before: XCTAssertTrue(calls.isEmpty)
            case .materials, .materialResult, .cancelledFailure: XCTAssertEqual(calls, ["materials"])
            case .fallback, .fallbackResult: XCTAssertEqual(calls, ["materials", "geometry"])
            case .geometryOnly: XCTAssertEqual(calls, ["geometry"])
            }
        }
    }

    func testEmptyDocumentFailsWithoutInvokingEitherRenderer() async throws {
        do {
            _ = try await FilePreviewRenderPolicy.render(
                document: FilePreviewDocument(mesh: nil, materials: nil, materialError: nil),
                renderMaterials: { _ in throw PreviewRenderFailure.unexpected },
                renderGeometry: { _ in throw PreviewRenderFailure.unexpected })
            XCTFail("No visible mesh cannot produce an object thumbnail")
        } catch let error as FilePreviewError {
            guard case .unavailable(let cause) = error else { return XCTFail("Expected empty geometry cause") }
            XCTAssertTrue(cause.contains("no visible mesh"))
        }
    }

    private func document(materials: MeshMaterialContent?, materialError: (any Error)? = nil) throws
        -> FilePreviewDocument
    {
        let baked = try BakedMetalFixture.quad()
        let mesh = IndexedMesh(
            vertices: baked.geometry.vertices, indices: baked.geometry.vertices.indices.map { UInt32($0) },
            nodeCount: 2, partCount: 1, warning: "")
        return FilePreviewDocument(mesh: mesh, materials: materials, materialError: materialError)
    }

    private func image(alpha: UInt8 = 255) throws -> FilePreviewImage {
        try FilePreviewImage(
            gpuPixels: Data([0, 0, alpha, alpha]),
            dimensions: FilePreviewDimensions(maximumSize: CGSize(width: 1, height: 1), scale: 1),
            isSRGBRenderTarget: false)
    }

    private enum CancellationPhase: CaseIterable {
        case before, materials, materialResult, cancelledFailure, fallback, fallbackResult, geometryOnly
    }
}

private enum PreviewRenderFailure: LocalizedError, Equatable {
    case preparation, material, geometry, unexpected
    var errorDescription: String? {
        switch self {
        case .preparation: "original preparation cause"
        case .material: "original material cause"
        case .geometry: "original geometry cause"
        case .unexpected: "unexpected renderer invoked"
        }
    }
}
