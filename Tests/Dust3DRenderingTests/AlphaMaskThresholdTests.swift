import XCTest

@testable import Dust3DRendering

final class AlphaMaskThresholdTests: XCTestCase {
    func testMatchesOriginalDoubleComparisonForAvailableFloatAlphaSamples() throws {
        let alphas: [Float] = [
            0, .leastNonzeroMagnitude, .leastNormalMagnitude, 0.25, 0.5, Float(128) / 255, Float(1).nextDown, 1,
        ]
        let cutoffs = [
            0.0, Double.leastNonzeroMagnitude, Double.leastNormalMagnitude,
            Double(Float.leastNonzeroMagnitude).nextDown, Double(Float.leastNonzeroMagnitude).nextUp,
            Double(0.5).nextDown, 0.5, Double(0.5).nextUp, Double(1).nextDown, 1, Double(1).nextUp, 1.5,
            Double.greatestFiniteMagnitude,
        ]
        for cutoff in cutoffs {
            let threshold = try AlphaMaskThreshold(cutoff)
            XCTAssertTrue(threshold.value.isFinite)
            for alpha in alphas {
                let accepted = alpha >= threshold.value && (!threshold.shouldExcludeZeroAlpha || alpha > 0)
                XCTAssertEqual(accepted, Double(alpha) >= cutoff, "Sample \(alpha), cutoff \(cutoff)")
            }
        }
    }

    func testKeepsZeroExclusionWhenGpuFlushesSubnormalThresholds() throws {
        for cutoff in [Double.leastNonzeroMagnitude, Double(Float.leastNonzeroMagnitude), Double.leastNormalMagnitude] {
            let threshold = try AlphaMaskThreshold(cutoff)
            XCTAssertTrue(threshold.shouldExcludeZeroAlpha)
            let flushed = threshold.value < Float.leastNormalMagnitude ? Float(0) : threshold.value
            for alpha: Float in [0, .leastNormalMagnitude, 0.5, 1] {
                let accepted = alpha >= flushed && (!threshold.shouldExcludeZeroAlpha || alpha > 0)
                XCTAssertEqual(accepted, Double(alpha) >= cutoff)
            }
        }
        let zero = try AlphaMaskThreshold(-0.0)
        XCTAssertEqual(zero.value, 0)
        XCTAssertFalse(zero.shouldExcludeZeroAlpha)
    }

    func testRejectsNegativeAndNonfiniteCutoffs() {
        for cutoff in [-Double.leastNonzeroMagnitude, -1, -.infinity, .infinity, .nan] {
            XCTAssertThrowsError(try AlphaMaskThreshold(cutoff)) {
                XCTAssertEqual($0 as? AlphaMaskThresholdError, .invalidValue)
            }
        }
    }
}
