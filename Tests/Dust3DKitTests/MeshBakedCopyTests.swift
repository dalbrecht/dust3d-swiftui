import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

final class MeshBakedCopyTests: XCTestCase {
    func testCopiesImageBytesAndPreservesOptionalAbsence() throws {
        var pixels: [UInt8] = [17, 91, 200, 128]
        let copied = try pixels.withUnsafeBufferPointer { buffer in
            var remaining = 4
            let view = Dust3DTextureView(width: 1, height: 1, row_stride: 4, byte_count: 4, pixels: buffer.baseAddress)
            let result = try MeshBakedCopy.image(view, required: true, remaining: &remaining)
            XCTAssertEqual(remaining, 0)
            return try XCTUnwrap(result)
        }
        pixels[0] = 99
        XCTAssertEqual(copied.pixels, Data([17, 91, 200, 128]))
        var remaining = 0
        XCTAssertNil(try MeshBakedCopy.image(Dust3DTextureView(), required: false, remaining: &remaining))
        XCTAssertThrowsError(try MeshBakedCopy.image(Dust3DTextureView(), required: true, remaining: &remaining))
    }

    func testRejectsIncompleteAndInvalidImageViewsBeforeReadingBuffers() throws {
        let pixels: [UInt8] = [1, 2, 3, 4]
        try pixels.withUnsafeBufferPointer { buffer in
            for view in [
                Dust3DTextureView(width: 1, height: 1, row_stride: 4, byte_count: 4, pixels: nil),
                Dust3DTextureView(width: Int.max, height: 1, row_stride: 4, byte_count: 4, pixels: buffer.baseAddress),
                Dust3DTextureView(width: 1, height: -1, row_stride: 4, byte_count: 4, pixels: buffer.baseAddress),
                Dust3DTextureView(width: 1, height: 1, row_stride: 3, byte_count: 4, pixels: buffer.baseAddress),
                Dust3DTextureView(width: 1, height: 1, row_stride: 4, byte_count: 3, pixels: buffer.baseAddress),
            ] {
                var remaining = 4
                XCTAssertThrowsError(try MeshBakedCopy.image(view, required: false, remaining: &remaining)) {
                    XCTAssertEqual(($0 as? MeshLoadingError)?.status, 3)
                }
            }
            var remaining = 3
            let view = Dust3DTextureView(width: 1, height: 1, row_stride: 4, byte_count: 4, pixels: buffer.baseAddress)
            XCTAssertThrowsError(try MeshBakedCopy.image(view, required: true, remaining: &remaining))
        }
    }

    func testPreservesKnownUnknownAndReflectedTangentFrames() throws {
        var value = Dust3DTextureTangent()
        value.handedness = 1
        XCTAssertFalse(try MeshBakedCopy.tangent(value).hasMapping)
        value.direction = (1, 0, 0)
        value.known = 1
        XCTAssertEqual(try MeshBakedCopy.tangent(value).direction, SIMD3<Float>(1, 0, 0))
        value.handedness = -1
        XCTAssertEqual(try MeshBakedCopy.tangent(value).handedness, -1)
        for invalid in [UInt8(2), UInt8.max] {
            value.known = invalid
            XCTAssertThrowsError(try MeshBakedCopy.tangent(value))
        }
        value.known = 1
        value.handedness = 0
        XCTAssertThrowsError(try MeshBakedCopy.tangent(value))
        value.handedness = 1
        value.direction = (2, 0, 0)
        XCTAssertThrowsError(try MeshBakedCopy.tangent(value))
        value.direction = (.nan, 0, 0)
        XCTAssertThrowsError(try MeshBakedCopy.tangent(value))
    }
}
