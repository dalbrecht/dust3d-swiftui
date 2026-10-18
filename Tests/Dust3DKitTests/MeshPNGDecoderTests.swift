import Foundation
import XCTest

@testable import Dust3DKit

final class MeshPNGDecoderTests: XCTestCase {
    func test_should_preserve_png_samples_in_straight_rgba8() throws {
        // Independently encoded PNG scanlines (Python stdlib zlib/CRC), not rendered snapshots.
        let fixtures: [(String, String, [UInt8])] = [
            (
                "gray-alpha-zero",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGMQZDjxHwAC2AHZjeSxLgAAAABJRU5ErkJggg==",
                [17, 17, 17, 0, 200, 200, 200, 255]
            ),
            (
                "gray-alpha16-zero",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAQAAAAOu2tCAAAAEUlEQVR4nGNg+M/A0MDw/z8AC/8DfnjcxdcAAAAASUVORK5CYII=",
                [1, 1, 1, 0, 128, 128, 128, 255]
            ),
            (
                "gray-transparent16",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAAAAACB2fwVAAAAAnRSTlMA/1uRIrUAAAANSURBVHicY2D438AAAAQCAYCVT7EmAAAAAElFTkSuQmCC",
                [1, 1, 1, 0, 128, 128, 128, 255]
            ),
            (
                "gray-transparent1",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQAAAADcWUInAAAAAnRSTlMAAQGU/a4AAAAKSURBVHicY2gAAACCAIF3zXK2AAAAAElFTkSuQmCC",
                [255, 255, 255, 0, 0, 0, 0, 255]
            ),
            (
                "gray-transparent2",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAgAAAACb+Tj3AAAAAnRSTlMAA++anIIAAAAKSURBVHicYzgAAADCAMFSXldRAAAAAElFTkSuQmCC",
                [0, 0, 0, 0, 0, 0, 0, 255]
            ),
            (
                "gray-transparent4",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABBAAAAAAUuc1XAAAAAnRSTlMAD+Ys0KkAAAAKSURBVHicY/gAAADyAPGc8R3mAAAAAElFTkSuQmCC",
                [0, 0, 0, 0, 0, 0, 0, 255]
            ),
            (
                "gray2", "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAgAAAACb+Tj3AAAACklEQVR4nGMwAAAAMgAxaciY+gAAAABJRU5ErkJggg==",
                [0, 0, 0, 255, 255, 255, 255, 255]
            ),
            (
                "gray4", "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABBAAAAAAUuc1XAAAACklEQVR4nGOwAQAAPgA9Ki4U4gAAAABJRU5ErkJggg==",
                [51, 51, 51, 255, 204, 204, 204, 255]
            ),
            (
                "gray16",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAAAAACB2fwVAAAADUlEQVR4nGNg+N/AAAAEAgGAlU+xJgAAAABJRU5ErkJggg==",
                [1, 1, 1, 255, 128, 128, 128, 255]
            ),
            (
                "gray-alpha16",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAQAAAAOu2tCAAAAEUlEQVR4nGNg+M/I2MBQ/x8ACwoDAHiba9wAAAAASUVORK5CYII=",
                [1, 1, 1, 1, 128, 128, 128, 127]
            ),
            (
                "rgb16",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAIAAAAr0DSeAAAAFUlEQVR4nGNg+N/QUP///38GhgYGACtoBfw3hzYxAAAAAElFTkSuQmCC",
                [1, 128, 127, 255, 255, 0, 128, 255]
            ),
            (
                "gray-transparent",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAAnRSTlMAERwj7coAAAALSURBVHicYxA8AQAA7QDaiakNYwAAAABJRU5ErkJggg==",
                [0, 0, 0, 0, 200, 200, 200, 255]
            ),
            (
                "rgb-transparent",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAABnRSTlMAEQBbAMjGcDJwAAAAD0lEQVR4nGMQjD6RYnQCAAesApOApbfWAAAAAElFTkSuQmCC",
                [17, 91, 200, 0, 100, 50, 200, 255]
            ),
            (
                "gray", "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAC0lEQVR4nGMQPAEAAO0A2ompDWMAAAAASUVORK5CYII=",
                [17, 17, 17, 255, 200, 200, 200, 255]
            ),
            (
                "gray-alpha",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGMQbDjBCAADWgFb2TfOwAAAAABJRU5ErkJggg==",
                [17, 17, 17, 128, 200, 200, 200, 1]
            ),
            (
                "gray1", "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQAAAADcWUInAAAACklEQVR4nGNwAAAAQgBBKTf07wAAAABJRU5ErkJggg==",
                [0, 0, 0, 255, 255, 255, 255, 255]
            ),
            (
                "palette",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAACklEQVR4nGNwAAAAQgBBKTf07wAAAABJRU5ErkJggg==",
                [255, 0, 0, 255, 0, 0, 255, 255]
            ),
            (
                "palette-alpha",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC",
                [255, 0, 0, 128, 0, 0, 255, 1]
            ),
            (
                "rgb",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAAD0lEQVR4nGMQjD6RYnQCAAesApOApbfWAAAAAElFTkSuQmCC",
                [17, 91, 200, 255, 100, 50, 200, 255]
            ),
            (
                "rgba16",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAYAAACksqPJAAAAGUlEQVR4nGNg+N/QUP+/geH/fwaGBgZGRgBDXwZ+SS6iGgAAAABJRU5ErkJggg==",
                [1, 128, 127, 128, 255, 0, 128, 1]
            ),
        ]
        for (name, encoded, expected) in fixtures {
            let data = try XCTUnwrap(Data(base64Encoded: encoded))
            let decoded = try MeshPNGDecoder.decode(data, imageID: "fixture")
            XCTAssertEqual(decoded.width, 2, name)
            XCTAssertEqual(decoded.height, 1, name)
            XCTAssertEqual(decoded.rowStride, 8, name)
            XCTAssertEqual(decoded.imageID, "fixture", name)
            XCTAssertEqual(Array(decoded.pixels), expected, name)
        }
    }

    func test_should_preserve_low_alpha_hidden_rgb_and_encoded_orientation() throws {
        let encoded =
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGmVYSWZJSSoACAAAAAEAEgEDAAEAAAAGAAAAAAAAALdIESkAAAAaSURBVHicYxCMPtGQYnSCkSE5wpfhPwPDfwA18gYaVyHuJgAAAABJRU5ErkJggg=="
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        let decoded = try MeshPNGDecoder.decode(data, imageID: "fixture")
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(Array(decoded.pixels), [17, 91, 200, 128, 100, 50, 200, 1, 99, 88, 77, 0, 255, 0, 0, 255])
        XCTAssertEqual(data, try XCTUnwrap(Data(base64Encoded: encoded)))
    }

    func test_should_reject_invalid_limits_and_malformed_chunk_spans() throws {
        let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAC0lEQVR4nGMQPAEAAO0A2ompDWMAAAAASUVORK5CYII="
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        for limit in [0, -1, Int.max] {
            XCTAssertThrowsError(try MeshPNGDecoder.decode(data, imageID: "fixture", maximumEncodedBytes: limit)) {
                XCTAssertEqual($0 as? MeshPNGDecodingError, .invalidLimits)
            }
            XCTAssertThrowsError(try MeshPNGDecoder.decode(data, imageID: "fixture", maximumDecodedBytes: limit)) {
                XCTAssertEqual($0 as? MeshPNGDecodingError, .invalidLimits)
            }
        }
        var variants = [Data(data.prefix(32)), data + Data([0])]
        for (offset, replacement) in [(0, UInt8(0)), (8, 255), (12, 0), (16, 255), (33, 255), (41, 0)] {
            var mutated = data
            mutated[offset] = replacement
            variants.append(mutated)
        }
        for variant in variants {
            XCTAssertThrowsError(try MeshPNGDecoder.decode(variant, imageID: "fixture"))
        }
    }

    func test_should_reject_invalid_and_over_budget_png_before_decoding() throws {
        XCTAssertThrowsError(try MeshPNGDecoder.decode(Data(), imageID: "fixture"))
        let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAC0lEQVR4nGMQPAEAAO0A2ompDWMAAAAASUVORK5CYII="
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertThrowsError(try MeshPNGDecoder.decode(data, imageID: "fixture", maximumEncodedBytes: 1))
        XCTAssertThrowsError(try MeshPNGDecoder.decode(data, imageID: "fixture", maximumDecodedBytes: 7))
        XCTAssertThrowsError(try MeshPNGDecoder.decode(data.dropLast(12), imageID: "fixture"))
    }
}
