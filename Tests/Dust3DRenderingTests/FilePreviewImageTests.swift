import AppKit
import XCTest

@testable import Dust3DRendering

final class FilePreviewImageTests: XCTestCase {
    func testShouldFitRequestedScaleAndPreserveAspectWithinPixelBudget() throws {
        let retina = try FilePreviewDimensions(maximumSize: CGSize(width: 256, height: 128), scale: 2)
        XCTAssertEqual(retina.pixelWidth, 512)
        XCTAssertEqual(retina.pixelHeight, 256)
        XCTAssertEqual(retina.pointSize, CGSize(width: 256, height: 128))
        let bounded = try FilePreviewDimensions(maximumSize: CGSize(width: 2000, height: 1000), scale: 2)
        XCTAssertEqual(bounded.pixelWidth, 2048)
        XCTAssertEqual(bounded.pixelHeight, 1024)
        XCTAssertEqual(bounded.pointSize, CGSize(width: 1024, height: 512))
        let extreme = try FilePreviewDimensions(maximumSize: CGSize(width: 1e300, height: 1), scale: 2)
        XCTAssertEqual(extreme.pixelWidth, 2048)
        XCTAssertEqual(extreme.pixelHeight, 1)
        for size in [CGSize.zero, CGSize(width: -1, height: 2), CGSize(width: CGFloat.infinity, height: 1)] {
            XCTAssertThrowsError(try FilePreviewDimensions(maximumSize: size, scale: 1))
        }
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertThrowsError(try FilePreviewDimensions(maximumSize: CGSize(width: 1, height: 1), scale: scale))
        }
    }

    func testShouldKeepFractionalReplySizesInsideTheRequestedPointBounds() throws {
        let dimensions = try FilePreviewDimensions(maximumSize: CGSize(width: 1.1, height: 0.6), scale: 1)
        XCTAssertLessThanOrEqual(dimensions.pointSize.width, 1.1)
        XCTAssertLessThanOrEqual(dimensions.pointSize.height, 0.6)
        XCTAssertEqual(
            dimensions.pointSize.width / dimensions.pointSize.height,
            CGFloat(dimensions.pixelWidth) / CGFloat(dimensions.pixelHeight), accuracy: 1e-12)
    }

    func testShouldStripReadbackPaddingAndRejectInvalidSpansOrCancellation() async throws {
        let dimensions = try FilePreviewDimensions(maximumSize: CGSize(width: 1, height: 2), scale: 1)
        let bytes = Data([10, 20, 30, 255, 99, 99, 99, 99, 40, 50, 60, 255])
        let image = try FilePreviewImage(
            gpuPixels: bytes, dimensions: dimensions, isSRGBRenderTarget: true, sourceRowStride: 8)
        XCTAssertEqual(image.pixels, Data([10, 20, 30, 255, 40, 50, 60, 255]))
        for stride in [0, -1, Int.max] {
            XCTAssertThrowsError(
                try FilePreviewImage(
                    gpuPixels: bytes, dimensions: dimensions, isSRGBRenderTarget: true, sourceRowStride: stride))
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FilePreviewImage(
                gpuPixels: bytes, dimensions: dimensions, isSRGBRenderTarget: true, sourceRowStride: 8)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled image conversion must fail")
        } catch is CancellationError {}
    }

    @MainActor
    func testShouldAllowSystemDrawingCallbackOnABackgroundExecutor() async throws {
        let dimensions = try FilePreviewDimensions(maximumSize: CGSize(width: 1, height: 1), scale: 2)
        let image = try FilePreviewImage(
            gpuPixels: Data([0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255]), dimensions: dimensions,
            isSRGBRenderTarget: true)
        let drawing = try image.makeDrawing()
        let output = try await Task.detached {
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(
                CGContext(
                    data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            XCTAssertTrue(drawing(context))
            let bytes = try XCTUnwrap(context.data)
            return Data(bytes: bytes, count: 16)
        }.value
        XCTAssertEqual(output, Data([255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255]))
    }

    func testShouldConvertLinearBlendedSRGBReadbackToCoreGraphicsPremultipliedSamples() throws {
        let dimensions = try FilePreviewDimensions(maximumSize: CGSize(width: 3, height: 1), scale: 1)
        // Linear red 1 * alpha .5 becomes about 188 in an sRGB GPU attachment.
        // Core Graphics expects encoded red premultiplied by alpha, approximately 128.
        let source = Data([0, 0, 188, 128, 12, 34, 56, 255, 200, 100, 50, 0])
        let image = try FilePreviewImage(gpuPixels: source, dimensions: dimensions, isSRGBRenderTarget: true)
        XCTAssertEqual(image.pixels[2], 128)
        XCTAssertEqual(image.pixels[3], 128)
        XCTAssertEqual(Array(image.pixels[4..<8]), [12, 34, 56, 255])
        XCTAssertEqual(Array(image.pixels[8..<12]), [0, 0, 0, 0])
        let representation = NSBitmapImageRep(cgImage: try image.makeCGImage())
        let color = try XCTUnwrap(representation.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.02)
        XCTAssertEqual(color.alphaComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(source[2], 188)
        let ordinary = try FilePreviewImage(gpuPixels: source, dimensions: dimensions, isSRGBRenderTarget: false)
        XCTAssertEqual(ordinary.pixels[2], 188)
        XCTAssertThrowsError(
            try FilePreviewImage(gpuPixels: Data([0]), dimensions: dimensions, isSRGBRenderTarget: true))
    }
}
