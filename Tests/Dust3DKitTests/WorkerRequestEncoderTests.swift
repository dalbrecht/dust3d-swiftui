import Foundation
import XCTest

@testable import Dust3DKit

final class WorkerRequestEncoderTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testBaseRequestOwnsFrameAndExpectedHeaderAfterEncodingReturns() async throws {
        var archive = try fixture()
        let document = try XCTUnwrap(UUID(uuidString: "00112233-4455-4677-8899-aabbccddeeff"))
        let identity = try WorkerRequestIdentity(document: document, request: 1, revision: 7)
        let packet = try WorkerRequestEncoder.encode(archive: archive, identity: identity)
        XCTAssertEqual(packet.identity, identity)
        XCTAssertEqual(packet.expectedHeader.count, 64)
        XCTAssertEqual(packet.frame.prefix(64), packet.expectedHeader)
        XCTAssertEqual(packet.frame.suffix(archive.count), archive)
        XCTAssertEqual(packet.frame.count, archive.count + 64)
        XCTAssertEqual(
            packet.expectedHeader.subdata(in: 40..<56),
            Data([
                0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x46, 0x77,
                0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
            ]), "The ABI document UUID uses source byte order")
        let retained = packet.frame
        _ = try WorkerRequestEncoder.encode(
            archive: archive, identity: WorkerRequestIdentity(document: UUID(), request: 2, revision: 8))
        archive.removeAll()
        XCTAssertEqual(packet.frame, retained)
        let transferred = await Task.detached { packet }.value
        XCTAssertEqual(transferred.frame, retained)
    }

    func testUvRequestCopiesOptionsAndPreservesOpaqueArchive() throws {
        let archive = try fixture()
        let identity = try WorkerRequestIdentity(document: UUID(), request: 3, revision: 0)
        let packet = try WorkerRequestEncoder.encode(
            archive: archive, identity: identity,
            operation: .uv(
                options: WorkerUvRequestOptions(
                    textureSize: 256, metadataBudget: 4096,
                    images: [.init(id: "{AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA}", width: 2, height: 4)])))
        XCTAssertEqual(packet.expectedHeader, packet.frame.prefix(64))
        XCTAssertGreaterThan(packet.frame.count, archive.count + 64)
        XCTAssertEqual(packet.frame.suffix(archive.count), archive)
        let changed = try WorkerRequestEncoder.encode(
            archive: archive, identity: identity, operation: .uv(options: .init(textureSize: 512)))
        XCTAssertNotEqual(packet.frame, changed.frame)
    }

    func testInvalidIdentityAndLimitsFailBeforeRetainingInput() throws {
        XCTAssertThrowsError(try WorkerRequestIdentity(document: UUID(), request: 0, revision: 1)) {
            XCTAssertEqual($0 as? WorkerRequestError, .invalidIdentity)
        }
        for size in [-1, 0, Int.max] {
            XCTAssertThrowsError(try WorkerRequestLimits(maximumInputBytes: size)) {
                XCTAssertEqual($0 as? WorkerRequestError, .invalidLimits)
            }
            XCTAssertThrowsError(try WorkerRequestLimits(maximumOutputBytes: size))
            XCTAssertThrowsError(try WorkerRequestLimits(maximumFailureBytes: size))
        }
        let zero = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertThrowsError(try WorkerRequestIdentity(document: zero, request: 1, revision: 0))
        let identity = try WorkerRequestIdentity(document: UUID(), request: 1, revision: 0)
        XCTAssertThrowsError(try WorkerRequestEncoder.encode(archive: Data(), identity: identity)) {
            XCTAssertEqual($0 as? WorkerRequestError, .emptyArchive)
        }
        XCTAssertThrowsError(
            try WorkerRequestEncoder.encode(
                archive: fixture(), identity: identity, limits: WorkerRequestLimits(maximumInputBytes: 1))
        ) {
            XCTAssertEqual($0 as? WorkerRequestError, .inputLimitExceeded)
        }
    }

    func testCoreUvRejectionPreservesOriginalNumericReceiptAndOwnedCause() throws {
        let archive = try fixture()
        let identity = try WorkerRequestIdentity(document: UUID(), request: 1, revision: 0)
        do {
            _ = try WorkerRequestEncoder.encode(
                archive: archive, identity: identity, operation: .uv(options: .init(textureSize: 8193)))
            XCTFail("Unsupported codec options must reject without generation")
        } catch WorkerRequestError.encoding(let receipt) {
            XCTAssertEqual(receipt.status, 2)
            XCTAssertEqual(receipt.source, 2)
            XCTAssertEqual(receipt.code, 6)
            XCTAssertFalse(receipt.isTruncated)
            XCTAssertFalse(receipt.cause.isEmpty)
            XCTAssertEqual(receipt.cause, Data("Worker UV request options are invalid.".utf8))
            XCTAssertEqual(
                WorkerRequestError.encoding(receipt).localizedDescription,
                "Worker UV request options are invalid.")
        }
        XCTAssertThrowsError(
            try WorkerRequestEncoder.encode(
                archive: archive, identity: identity,
                operation: .uv(options: .init(images: [.init(id: "short", width: 1, height: 1)])))
        ) {
            XCTAssertEqual($0 as? WorkerRequestError, .invalidOptions)
        }
    }
}
