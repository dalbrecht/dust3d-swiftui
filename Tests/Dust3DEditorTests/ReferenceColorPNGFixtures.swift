import CoreGraphics
import Foundation
import XCTest

@testable import Dust3DEditor

/// Independent tiny PNG scanlines encoded with Python stdlib zlib/CRC; no rendered snapshot baseline.
enum ReferenceColorPNGFixtures {
    static func customGrayPNG() throws -> Data {
        let white: [CGFloat] = [0.95047, 1, 1.08883]
        let space = try XCTUnwrap(CGColorSpace(calibratedGrayWhitePoint: white, blackPoint: nil, gamma: 1.8))
        let provider = try XCTUnwrap(CGDataProvider(data: Data([17, 100, 200, 250]) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2,
                space: space, bitmapInfo: .init(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try ReferenceImageCodec.encodePNG(image)
    }

    static let orientations: [Int: String] = [
        1:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAABAAAAAAAAAL2NGDAAAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
        2:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAACAAAAAAAAADMCH9MAAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
        3:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAADAAAAAAAAAP+oH00AAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
        4:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAAEAAAAAAAAAPVtFlQAAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
        5:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAAFAAAAAAAAADnHFsoAAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
        6:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAAGAAAAAAAAALdIESkAAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
        7:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAAHAAAAAAAAAHviEbcAAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
        8:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAAIAAAAAAAAAKLCAxsAAAAjSURBVHicY+AWlWfgEVNgZOAVV2zgk1D6z8AvqfxfQErlPwAs3gUmjNlefgAAAABJRU5ErkJggg==",
    ]
}
