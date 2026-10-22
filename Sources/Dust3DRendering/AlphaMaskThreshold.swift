enum AlphaMaskThresholdError: Error, Sendable, Equatable { case invalidValue }

/// Compare available Float alpha samples against the original nonnegative Double cutoff.
struct AlphaMaskThreshold: Sendable {
    let value: Float
    let shouldExcludeZeroAlpha: Bool

    init(_ cutoff: Double) throws {
        guard cutoff.isFinite, cutoff >= 0 else { throw AlphaMaskThresholdError.invalidValue }
        shouldExcludeZeroAlpha = cutoff > 0
        if cutoff > 1 {
            value = 2
        } else {
            let nearest = Float(cutoff)
            // Rounding downward would incorrectly admit a Float sample below the source cutoff.
            value = Double(nearest) < cutoff ? nearest.nextUp : nearest
        }
        // The shader also checks shouldExcludeZeroAlpha: GPUs may flush a subnormal
        // threshold to zero, but a positive source cutoff must still exclude zero alpha.
    }
}
