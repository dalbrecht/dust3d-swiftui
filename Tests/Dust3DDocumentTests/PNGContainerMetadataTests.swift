import Foundation
import XCTest

@testable import Dust3DDocument

final class PNGContainerMetadataTests: XCTestCase {
    private func image(
        width: UInt32 = 2, height: UInt32 = 1, bitDepth: UInt8 = 8, colorType: UInt8 = 6, transparency: Bool = false
    ) -> Data {
        func integer(_ value: UInt32) -> [UInt8] {
            [UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
        }
        func chunk(_ name: String, _ bytes: [UInt8]) -> Data {
            Data(integer(UInt32(bytes.count)) + Array(name.utf8) + bytes + [0, 0, 0, 0])
        }
        return Data([137, 80, 78, 71, 13, 10, 26, 10])
            + chunk("IHDR", integer(width) + integer(height) + [bitDepth, colorType, 0, 0, 0])
            + (transparency ? chunk("tRNS", [0, 0]) : Data()) + chunk("IDAT", [1]) + chunk("IEND", [])
    }
    func testShouldInspectBoundedStructureWithoutDecodingPixels() throws {
        let data = image(transparency: true)
        let result = try PNGContainerMetadata(data: data, maximumEncodedBytes: data.count, maximumDecodedBytes: 8)
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 1)
        XCTAssertEqual(result.bitDepth, 8)
        XCTAssertEqual(result.colorType, 6)
        XCTAssertTrue(result.hasTransparencyKey)
        XCTAssertFalse(try PNGContainerMetadata(data: image()).hasTransparencyKey)
        for (color, depths) in [
            (0, [1, 2, 4, 8, 16]), (2, [8, 16]), (3, [1, 2, 4, 8]), (4, [8, 16]), (6, [8, 16]),
        ] {
            for depth in depths {
                _ = try PNGContainerMetadata(data: image(bitDepth: UInt8(depth), colorType: UInt8(color)))
            }
        }
    }
    func testShouldRejectInvalidQuotasDimensionsAndDecodedStorage() throws {
        let data = image()
        for limit in [0, -1, Int.max] {
            XCTAssertThrowsError(try PNGContainerMetadata(data: data, maximumEncodedBytes: limit)) {
                XCTAssertEqual($0 as? PNGContainerError, .invalidLimits)
            }
            XCTAssertThrowsError(try PNGContainerMetadata(data: data, maximumDecodedBytes: limit)) {
                XCTAssertEqual($0 as? PNGContainerError, .invalidLimits)
            }
        }
        XCTAssertThrowsError(try PNGContainerMetadata(data: data, maximumEncodedBytes: data.count - 1)) {
            XCTAssertEqual($0 as? PNGContainerError, .encodedLimitExceeded)
        }
        for dimensions in [(UInt32(0), UInt32(1)), (8193, 1), (1, 8193), (UInt32.max, UInt32.max)] {
            XCTAssertThrowsError(try PNGContainerMetadata(data: image(width: dimensions.0, height: dimensions.1))) {
                XCTAssertEqual($0 as? PNGContainerError, .decodedLimitExceeded)
            }
        }
        XCTAssertThrowsError(try PNGContainerMetadata(data: data, maximumDecodedBytes: 7)) {
            XCTAssertEqual($0 as? PNGContainerError, .decodedLimitExceeded)
        }
    }
    func testShouldRejectMalformedEnvelopeAndUnsupportedIHDR() throws {
        let original = image()
        var malformed = [
            Data(), Data([137]), Data(original.dropLast()), original + Data([0]), Data(original.prefix(33)),
        ]
        for (offset, value) in [
            (0, UInt8(0)), (11, 12), (12, 0), (24, 3), (25, 1), (26, 1), (27, 1), (28, 2), (36, 255),
        ] {
            var changed = original
            changed[offset] = value
            malformed.append(changed)
        }
        var noIDAT = original
        noIDAT.replaceSubrange(37..<41, with: Data("abcd".utf8))
        malformed.append(noIDAT)
        var duplicateIHDR = original
        duplicateIHDR.insert(contentsOf: original[8..<33], at: 33)
        malformed.append(duplicateIHDR)
        for data in malformed {
            XCTAssertThrowsError(try PNGContainerMetadata(data: data)) {
                XCTAssertEqual($0 as? PNGContainerError, .invalidPNG)
            }
        }
        var interlaced = original
        interlaced[28] = 1
        _ = try PNGContainerMetadata(data: interlaced)
    }
    func testShouldExposeActionableContainerDiagnostics() {
        for (error, expected) in [
            (PNGContainerError.invalidLimits, "positive"), (.encodedLimitExceeded, "encoded PNG"),
            (.invalidPNG, "PNG container"), (.decodedLimitExceeded, "dimensions"),
        ] {
            XCTAssertTrue(error.localizedDescription.contains(expected))
        }
    }

}
