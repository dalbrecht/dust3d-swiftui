import Foundation
import XCTest

@testable import Dust3DEditor

final class FishIdleFbxCopyTests: XCTestCase {
    func testCopyRequiresExactBoundedFBX7400Bytes() throws {
        let bytes = Data("Kaydara FBX Binary  \0\u{1a}\0".utf8) + Data([0xe8, 0x1c, 0, 0, 42])
        let limits = FishIdleCopyLimits(nativeBytes: 64, swiftBytes: 64, combinedBytes: 64)
        let copy = try FishIdleFbxCopy.copy(byteCount: bytes.count, limits: limits) { _ in bytes }
        XCTAssertEqual(copy, bytes)
        XCTAssertThrowsError(
            try FishIdleFbxCopy.copy(byteCount: 33, limits: limits) { _ in
                XCTFail("Oversized owner read bytes")
                return bytes
            }
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .payloadLimit) }
        XCTAssertThrowsError(
            try FishIdleFbxCopy.copy(byteCount: bytes.count, limits: limits) { _ in bytes.dropLast() }
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .nativeReceipt) }
        var wrongVersion = bytes
        wrongVersion[23] = 0
        XCTAssertThrowsError(
            try FishIdleFbxCopy.copy(byteCount: wrongVersion.count, limits: limits) { _ in wrongVersion }
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .nativeReceipt) }
    }
}
