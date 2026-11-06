/// Integer sample processing for the frozen Qt 6.12 ARM64 raster reference.
/// The native application has no Qt dependency. Keep this separate from the
/// generic PNG decoder, whose bake contract preserves unassociated channels.
enum ReferenceColorAlphaSample {
    static func fit(
        _ rgba: (Int, Int, Int, Int), singlePixel: Bool, sourceDepth: Int, vectorLane: Bool
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        func byte(_ value: Int) -> UInt8 {
            let rounded = value + 128
            return UInt8(clamping: (rounded - (rounded >> 8)) >> 8)
        }
        let samples: (Int, Int, Int, Int)
        if singlePixel && sourceDepth == 16 {
            // Qt's one-pixel image path reads pixel() as RGBA8 before filling
            // even an RGBA64 target. Other wide-image paths keep source precision.
            samples = (
                Int(byte(rgba.0)) * 257, Int(byte(rgba.1)) * 257,
                Int(byte(rgba.2)) * 257, Int(byte(rgba.3)) * 257
            )
        } else {
            samples = rgba
        }
        let alpha = samples.3
        guard alpha != 0 else { return (0, 0, 0, 0) }
        func channel(_ value: Int) -> UInt8 {
            if alpha == 65535 { return byte(value) }
            if singlePixel && sourceDepth == 8 {
                let a = Int(byte(alpha))
                let associated = (Int(byte(value)) * a + 127) / 255
                return UInt8(clamping: (associated * 255 + a / 2) / a)
            }
            let associated: Int
            if sourceDepth == 8 && vectorLane {
                // ARM64's four-pixel conversion approximates the 255-to-257
                // expansion after multiplying the original 8-bit channels.
                let product = Int(byte(value)) * Int(byte(alpha))
                associated = product + product / 128
            } else {
                associated = (value * alpha + 32767) / 65535
            }
            let unassociated = (associated * 65535 + alpha / 2) / alpha
            return byte(min(65535, unassociated))
        }
        return (channel(samples.0), channel(samples.1), channel(samples.2), byte(alpha))
    }
}
