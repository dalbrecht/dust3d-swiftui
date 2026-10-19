import Foundation
import XCTest

@testable import Dust3DDocument

final class JPEGContainerMetadataTests: XCTestCase {
    // Structural fixtures deliberately omit codec tables; they test the envelope, not pixel decoding.
    private func envelope(frame: UInt8 = 0xC0, width: Int = 2, height: Int = 3) -> Data {
        Data([
            0xFF, 0xD8, 0xFF, frame, 0, 11, 8,
            UInt8(height >> 8), UInt8(height & 255), UInt8(width >> 8), UInt8(width & 255),
            1, 1, 0x11, 0, 0xFF, 0xDA, 0, 8, 1, 1, 0, 0, 63, 0,
            1, 0xFF, 0, 2, 0xFF, 0xD0, 3, 0xFF, 0xD9,
        ])
    }

    func test_should_inspect_baseline_and_progressive_dimensions() throws {
        for frame: UInt8 in [0xC0, 0xC1, 0xC2] {
            let metadata = try JPEGContainerMetadata(data: envelope(frame: frame))
            XCTAssertEqual(metadata.width, 2)
            XCTAssertEqual(metadata.height, 3)
            XCTAssertEqual(metadata.componentCount, 1)
            XCTAssertEqual(metadata.isProgressive, frame == 0xC2)
        }
    }

    func test_should_reject_truncated_and_trailing_bytes() {
        let original = envelope()
        for count in 0..<original.count {
            XCTAssertThrowsError(try JPEGContainerMetadata(data: original.prefix(count)))
        }
        XCTAssertThrowsError(try JPEGContainerMetadata(data: original + Data([0])))
    }

    func test_should_enforce_limits_before_decoding() {
        XCTAssertThrowsError(try JPEGContainerMetadata(data: envelope(), maximumEncodedBytes: 0)) {
            XCTAssertEqual($0 as? JPEGContainerError, .invalidLimits)
        }
        XCTAssertThrowsError(try JPEGContainerMetadata(data: envelope(), maximumEncodedBytes: 1)) {
            XCTAssertEqual($0 as? JPEGContainerError, .encodedLimitExceeded)
        }
        XCTAssertThrowsError(try JPEGContainerMetadata(data: envelope(), maximumDecodedBytes: 23)) {
            XCTAssertEqual($0 as? JPEGContainerError, .decodedLimitExceeded)
        }
        XCTAssertThrowsError(try JPEGContainerMetadata(data: envelope(width: 8193))) {
            XCTAssertEqual($0 as? JPEGContainerError, .decodedLimitExceeded)
        }
    }

    func test_should_reject_unsupported_frames_and_precision() {
        XCTAssertThrowsError(try JPEGContainerMetadata(data: envelope(frame: 0xC3))) {
            XCTAssertEqual($0 as? JPEGContainerError, .unsupportedJPEG)
        }
        var bytes = envelope()
        bytes[6] = 12
        XCTAssertThrowsError(try JPEGContainerMetadata(data: bytes)) {
            XCTAssertEqual($0 as? JPEGContainerError, .unsupportedJPEG)
        }
    }
    func test_should_reject_invalid_markers_components_scans_and_dimension_redefinition() {
        var cases: [Data] = []
        var marker = envelope()
        marker[2] = 0
        cases.append(marker)
        var nestedStart = envelope()
        nestedStart[3] = 216
        cases.append(nestedStart)
        var components = envelope()
        components[11] = 2
        cases.append(components)
        var scan = envelope()
        scan[19] = 0
        cases.append(scan)
        var redefinition = envelope()
        redefinition.insert(contentsOf: [255, 220, 0, 4, 0, 2], at: 15)
        cases.append(redefinition)
        for bytes in cases { XCTAssertThrowsError(try JPEGContainerMetadata(data: bytes)) }
    }

}
