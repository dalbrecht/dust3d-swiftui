import Metal
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class FilePreviewRenderingTests: XCTestCase {
    func testShouldRenderRequestedDimensionsAndTransparentPixelsThroughProductionEncoder() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device is available") }
        let mesh = try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, 128]))
        // Non-aligned width exercises padded Metal readback rows, not only square atlas examples.
        let image = try await FilePreviewRenderer.render(
            bakedMesh: mesh, maximumSize: CGSize(width: 13, height: 7), scale: 1)
        XCTAssertEqual(image.width, 13)
        XCTAssertEqual(image.height, 7)
        XCTAssertEqual(image.rowStride, 52)
        XCTAssertEqual(image.pixels.count, 364)
        XCTAssertEqual(image.pixels[3], 0)
        let center = (3 * 13 + 6) * 4
        XCTAssertEqual(image.pixels[center + 3], 128)
        XCTAssertGreaterThan(image.pixels[center + 2], image.pixels[center])
        XCTAssertLessThanOrEqual(image.pixels[center + 2], 128)
        XCTAssertEqual(try image.makeCGImage().width, 13)
    }

    func testShouldRenderOrdinaryGeometryWhenOptionalMaterialsFail() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device is available") }
        let source = try BakedMetalFixture.quad(layers: [.init(color: SIMD4(0, 1, 0, 1))]).geometry
        let mesh = IndexedMesh(
            vertices: source.vertices, indices: [0, 1, 2, 3, 4, 5], nodeCount: 1, partCount: 1, warning: "")
        let image = try await FilePreviewRenderer.render(
            mesh: mesh, maximumSize: CGSize(width: 13, height: 7), scale: 1)
        let center = (3 * 13 + 6) * 4
        XCTAssertEqual(image.pixels[center + 3], 255)
        XCTAssertGreaterThan(image.pixels[center + 1], image.pixels[center + 2])
        XCTAssertEqual(image.pixels[3], 0)
    }

    func testShouldRejectCancelledAndInvalidPreviewRequestsBeforeRendering() async throws {
        let mesh = try BakedMetalFixture.quad()
        do {
            _ = try await FilePreviewRenderer.render(bakedMesh: mesh, maximumSize: .zero, scale: 1)
            XCTFail("Invalid dimensions must fail")
        } catch { XCTAssertEqual(error as? FilePreviewError, .invalidDimensions) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FilePreviewRenderer.render(
                bakedMesh: mesh, maximumSize: CGSize(width: 64, height: 64), scale: 1)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled rendering must fail")
        } catch is CancellationError {}
    }
}
