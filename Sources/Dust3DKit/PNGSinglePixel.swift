import Compression
import Dust3DDocument
import Foundation

/// ImageIO on some supported macOS versions zeros RGB for a transparent 1x1
/// RGBA8 image. Decode that one scanline independently to keep encoded channels.
/// This is not a general PNG decoder: the normal ImageIO validation still runs.
enum PNGSinglePixel {
    static func rgba8(_ png: Data, dimensions: PNGContainerMetadata) throws -> (UInt8, UInt8, UInt8, UInt8)? {
        guard dimensions.width == 1, dimensions.height == 1,
            dimensions.bitDepth == 8, dimensions.colorType == 6
        else { return nil }
        var compressed = Data()
        try png.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 8
            while offset <= bytes.count - 12 {
                try Task.checkCancellation()
                let count = bytes[offset..<offset + 4].reduce(0) { $0 * 256 + Int($1) }
                guard count <= bytes.count - offset - 12 else { throw MeshPNGDecodingError.invalidPNG }
                if bytes[offset + 4..<offset + 8].elementsEqual([73, 68, 65, 84]) {
                    // All IDAT data together is smaller than the already bounded PNG.
                    compressed.append(contentsOf: bytes[offset + 8..<offset + 8 + count])
                }
                offset += count + 12
            }
        }
        guard compressed.count >= 6 else { throw MeshPNGDecodingError.invalidPNG }
        var row = [UInt8](repeating: 0, count: 6)
        let count = try compressed.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Int in
            let cmf = input[0]
            let flags = input[1]
            guard cmf & 15 == 8, cmf >> 4 <= 7, flags & 32 == 0,
                (Int(cmf) * 256 + Int(flags)) % 31 == 0,
                let base = input.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else { throw MeshPNGDecodingError.invalidPNG }
            // Apple's ZLIB algorithm takes raw DEFLATE, without the RFC1950 wrapper.
            // Six output bytes detect an overlong scanline without an unbounded allocation.
            return try row.withUnsafeMutableBufferPointer { output in
                guard let destination = output.baseAddress else { throw MeshPNGDecodingError.invalidPNG }
                return compression_decode_buffer(
                    destination, output.count, base + 2, input.count - 6, nil, COMPRESSION_ZLIB)
            }
        }
        guard count == 5, row[0] <= 4 else { throw MeshPNGDecodingError.invalidPNG }
        var first: UInt32 = 1
        var second: UInt32 = 0
        for value in row.prefix(5) {
            first = (first + UInt32(value)) % 65521
            second = (second + first) % 65521
        }
        let checksum = compressed.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard checksum == ((second << 16) | first) else { throw MeshPNGDecodingError.invalidPNG }
        try Task.checkCancellation()
        // One pixel has no left/previous-row neighbors: all five PNG filters
        // therefore have a zero predictor. Adam7's other passes are empty too.
        return (row[1], row[2], row[3], row[4])
    }
}
