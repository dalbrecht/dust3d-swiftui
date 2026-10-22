import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

final class TextureMipChainTests: XCTestCase {
    func testCopiesOddDimensionChainAndRetainsPixelsAfterBorrowEnds() throws {
        var bytes = [UInt8](repeating: 37, count: (3 * 3 + 1) * 4)
        var remaining = bytes.count
        var budget = SourceBakeCopyBudget(maximum: 4096)
        let chain = try bytes.withUnsafeBufferPointer { storage in
            try TextureMipChainCopy.copy(
                count: 2, required: true, maximumSamplingLod: 1, nativeRemaining: &remaining, budget: &budget
            ) { level in
                let side = level == 0 ? 3 : 1
                return Dust3DTextureView(
                    width: side, height: side, row_stride: side * 4, byte_count: side * side * 4,
                    pixels: storage.baseAddress?.advanced(by: level == 0 ? 0 : 36))
            }
        }
        for index in bytes.indices { bytes[index] = 0 }
        bytes = []
        let owned = try XCTUnwrap(chain)
        XCTAssertEqual(owned.levels.map(\.width), [3, 1])
        XCTAssertEqual(owned.levels[1].pixels, Data(repeating: 37, count: 4))
        XCTAssertEqual(owned.maximumSamplingLod, 1)
        XCTAssertEqual(remaining, 0)
        XCTAssertGreaterThan(budget.used, 40)
    }

    func testRetainsRectangularAndPartialChainsWithoutInventingMissingLevels() throws {
        let images = [(8, 4), (4, 2), (2, 1), (1, 1)].map { width, height in
            MeshTextureImage(
                width: width, height: height, rowStride: width * 4,
                pixels: Data(repeating: 73, count: width * height * 4))
        }
        XCTAssertEqual(try TextureMipChain(levels: images, maximumSamplingLod: 3).levels.count, 4)
        XCTAssertEqual(try TextureMipChain(levels: Array(images.prefix(2)), maximumSamplingLod: 1).levels.count, 2)
        XCTAssertThrowsError(try TextureMipChain(levels: Array(images.prefix(2)), maximumSamplingLod: 1.01))
    }

    func testRejectsMissingAndExcessiveLevelsBeforeReadingAnyPointer() throws {
        for count in [-1, 0, 15, Int.max] {
            var remaining = 4096
            var budget = SourceBakeCopyBudget(maximum: 4096)
            XCTAssertThrowsError(
                try TextureMipChainCopy.copy(
                    count: count, required: true, maximumSamplingLod: 0,
                    nativeRemaining: &remaining, budget: &budget
                ) { _ in
                    XCTFail("Invalid count must reject before invoking the accessor")
                    return Dust3DTextureView()
                })
        }
        var remaining = 0
        var budget = SourceBakeCopyBudget(maximum: 1)
        XCTAssertNil(
            try TextureMipChainCopy.copy(
                count: 0, required: false, maximumSamplingLod: 0, nativeRemaining: &remaining, budget: &budget
            ) { _ in
                XCTFail("Absent optional maps have no borrowed view")
                return Dust3DTextureView()
            })
    }

    func testRejectsUnsupportedSamplingCapsAndMalformedOwnedLevels() throws {
        let base = MeshTextureImage(width: 2, height: 2, rowStride: 8, pixels: Data(repeating: 0, count: 16))
        let tip = MeshTextureImage(width: 1, height: 1, rowStride: 4, pixels: Data(repeating: 0, count: 4))
        for lod in [-1.0, Double.nan, .infinity, 1.01] {
            XCTAssertThrowsError(try TextureMipChain(levels: [base, tip], maximumSamplingLod: lod))
        }
        XCTAssertThrowsError(try TextureMipChain(levels: [], maximumSamplingLod: 0))
        XCTAssertThrowsError(try TextureMipChain(levels: [base, base], maximumSamplingLod: 0))
        XCTAssertThrowsError(try TextureMipChain(levels: [tip, tip], maximumSamplingLod: 0))
        XCTAssertThrowsError(
            try TextureMipChain(
                levels: [MeshTextureImage(width: 2, height: 2, rowStride: 9, pixels: Data(repeating: 0, count: 18))],
                maximumSamplingLod: 0))
        XCTAssertEqual(try TextureMipChain(levels: [base, tip], maximumSamplingLod: 0.5).maximumSamplingLod, 0.5)
    }
    func testChargesExactAggregateCopiedBytesAcrossEveryLevel() throws {
        let measured = try copySmallChain(maximum: 4096)
        XCTAssertEqual(try copySmallChain(maximum: measured), measured)
        XCTAssertThrowsError(try copySmallChain(maximum: measured - 1)) {
            XCTAssertEqual($0 as? SourceMeshBakeError, .copyLimitExceeded)
        }
    }

    func testRejectsNativeByteClaimsMalformedDimensionsAndNullViews() throws {
        var bytes = [UInt8](repeating: 71, count: 64)
        try bytes.withUnsafeMutableBufferPointer { storage in
            for mode in 0..<4 {
                var remaining = mode == 0 ? 15 : 4096
                var budget = SourceBakeCopyBudget(maximum: 4096)
                XCTAssertThrowsError(
                    try TextureMipChainCopy.copy(
                        count: mode == 1 ? 2 : 1, required: true, maximumSamplingLod: 0,
                        nativeRemaining: &remaining, budget: &budget
                    ) { level in
                        let width = mode == 1 && level == 1 ? 1 : 4
                        return Dust3DTextureView(
                            width: width, height: width, row_stride: width * 4,
                            byte_count: mode == 2 ? 1 : width * width * 4,
                            pixels: mode == 3 ? nil : UnsafePointer(storage.baseAddress))
                    })
            }
        }
    }

    func testPreservesAccessorFailureWithoutPublishingAPartialChain() throws {
        enum Failure: Error { case original }
        var remaining = 4096
        var budget = SourceBakeCopyBudget(maximum: 4096)
        XCTAssertThrowsError(
            try TextureMipChainCopy.copy(
                count: 1, required: true, maximumSamplingLod: 0, nativeRemaining: &remaining, budget: &budget
            ) { _ in throw Failure.original }
        ) {
            XCTAssertEqual($0 as? Failure, .original)
        }
    }

    func testCancellationBeforeAndDuringBorrowNeverPublishesAnImage() async throws {
        for shouldCancelDuringBorrow in [false, true] {
            let task = Task {
                if !shouldCancelDuringBorrow { withUnsafeCurrentTask { $0?.cancel() } }
                var remaining = 4096
                var budget = SourceBakeCopyBudget(maximum: 4096)
                return try TextureMipChainCopy.copy(
                    count: 1, required: true, maximumSamplingLod: 0, nativeRemaining: &remaining, budget: &budget
                ) { _ in
                    XCTAssertTrue(shouldCancelDuringBorrow, "Pre-cancelled work must not borrow")
                    withUnsafeCurrentTask { $0?.cancel() }
                    return Dust3DTextureView()
                }
            }
            do {
                _ = try await task.value
                XCTFail("Cancelled copying must not publish")
            } catch is CancellationError {}
        }
    }

    func testEveryMipValidationErrorHasAnActionableSpecificDescription() {
        let errors: [TextureMipChainError] = [
            .invalidLevelCount, .invalidImage, .invalidDimensions, .invalidSamplingLod,
        ]
        XCTAssertEqual(Set(errors.map(\.localizedDescription)).count, errors.count)
        for error in errors { XCTAssertFalse(error.localizedDescription.contains("couldn’t be completed")) }
    }

    private func copySmallChain(maximum: Int) throws -> Int {
        let pixels = [UInt8](repeating: 9, count: 20)
        var remaining = pixels.count
        var budget = SourceBakeCopyBudget(maximum: maximum)
        let result = try pixels.withUnsafeBufferPointer { storage in
            try TextureMipChainCopy.copy(
                count: 2, required: true, maximumSamplingLod: 1, nativeRemaining: &remaining, budget: &budget
            ) { level in
                let side = level == 0 ? 2 : 1
                return Dust3DTextureView(
                    width: side, height: side, row_stride: side * 4, byte_count: side * side * 4,
                    pixels: storage.baseAddress?.advanced(by: level == 0 ? 0 : 16))
            }
        }
        XCTAssertEqual(try XCTUnwrap(result).levels.count, 2)
        XCTAssertEqual(remaining, 0)
        return budget.used
    }

}
