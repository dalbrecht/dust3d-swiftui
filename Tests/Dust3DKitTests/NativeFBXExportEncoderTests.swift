import Foundation
import XCTest

@testable import Dust3DKit

private final class RecordedFBXEncoding: FBXExportOperation, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<DocumentExportArtifact, MeshLoadingError>
    private let cancels: Bool
    private var calls: [(Data, Int, Int, Bool)] = []
    init(_ result: Result<DocumentExportArtifact, MeshLoadingError>, cancels: Bool = false) {
        self.result = result
        self.cancels = cancels
    }
    func encode(archive: Data, maximumGeometryPayloadBytes: Int, maximumOutputPayloadBytes: Int) throws
        -> DocumentExportArtifact
    {
        lock.withLock {
            calls.append((archive, maximumGeometryPayloadBytes, maximumOutputPayloadBytes, Thread.isMainThread))
        }
        if cancels { withUnsafeCurrentTask { $0?.cancel() } }
        return try result.get()
    }
    var recorded: [(Data, Int, Int, Bool)] { lock.withLock { calls } }
}

/// Injected policy cases only; fake bytes never reach a foreign function.
@MainActor
final class NativeFBXExportEncoderTests: XCTestCase {
    func testBudgetsAndArchiveCountsRejectBeforeNativeDispatch() throws {
        XCTAssertNoThrow(try NativeFBXExportEncoder(maximumGeometryPayloadBytes: 1024, maximumOutputPayloadBytes: 1024))
        let operation = RecordedFBXEncoding(.success(.init(bytes: Data([1]), warning: "")))
        for invalid in [0, -1, 256 * 1024 * 1024 + 1, Int.max] {
            XCTAssertThrowsError(
                try NativeFBXExportEncoder(
                    maximumGeometryPayloadBytes: invalid, maximumOutputPayloadBytes: 1024, operation: operation))
            XCTAssertThrowsError(
                try NativeFBXExportEncoder(
                    maximumGeometryPayloadBytes: 1024, maximumOutputPayloadBytes: invalid, operation: operation))
        }
        for count in [0, -1, MeshLoader.maximumFileSize + 1, Int.max] {
            XCTAssertThrowsError(try NativeFBXExportEncoder.validateArchiveByteCount(count))
        }
        XCTAssertTrue(operation.recorded.isEmpty)
    }

    func testCopiedPayloadAdmissionUsesCheckedCountsWithoutLargeAllocations() throws {
        XCTAssertNoThrow(try NativeFBXExportEncoder.validateCopiedOutput(bytes: 2, warningBytes: 1, maximum: 3))
        for (bytes, warning) in [(0, 0), (-1, 0), (4, 0), (1, -1), (1, 4097), (Int.max, 1), (1, Int.max)] {
            XCTAssertThrowsError(
                try NativeFBXExportEncoder.validateCopiedOutput(bytes: bytes, warningBytes: warning, maximum: 3))
        }
    }

    func testOwnedBytesBudgetsAndOriginalWarningRemainOffMainThread() async throws {
        let expected = DocumentExportArtifact(bytes: Data([1, 2]), warning: "original FBX warning")
        let operation = RecordedFBXEncoding(.success(expected))
        let encoder = try NativeFBXExportEncoder(
            maximumGeometryPayloadBytes: 2048, maximumOutputPayloadBytes: 1024, operation: operation)
        let archive = Data([7, 8])
        let result = try await encoder.encode(archive: archive, format: .fbx)
        XCTAssertEqual(result, expected)
        let call = try XCTUnwrap(operation.recorded.first)
        XCTAssertEqual(operation.recorded.count, 1)
        XCTAssertEqual(call.0, archive)
        XCTAssertEqual(call.1, 2048)
        XCTAssertEqual(call.2, 1024)
        XCTAssertFalse(call.3)
    }

    func testFormatAndInputRejectBeforeInjectedWork() async throws {
        let operation = RecordedFBXEncoding(.success(.init(bytes: Data([1]), warning: "")))
        let encoder = try NativeFBXExportEncoder(
            maximumGeometryPayloadBytes: 1024, maximumOutputPayloadBytes: 1024, operation: operation)
        do {
            _ = try await encoder.encode(archive: Data([1]), format: .obj)
            XCTFail("A different format must not be substituted")
        } catch let error as NativeFBXExportError { XCTAssertEqual(error, .unsupportedFormat(.obj)) }
        do {
            _ = try await encoder.encode(archive: Data(), format: .fbx)
            XCTFail("Empty input must reject before dispatch")
        } catch is NativeFBXExportError {}
        XCTAssertTrue(operation.recorded.isEmpty)
    }

    func testInjectedErrorsAndInvalidOutputCannotPublish() async throws {
        let original = MeshLoadingError(status: 3, message: "original FBX cause")
        let failing = try NativeFBXExportEncoder(
            maximumGeometryPayloadBytes: 1024, maximumOutputPayloadBytes: 1024,
            operation: RecordedFBXEncoding(.failure(original)))
        do {
            _ = try await failing.encode(archive: Data([1]), format: .fbx)
            XCTFail("Original failure was hidden")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, original.status)
            XCTAssertEqual(error.message, original.message)
        }
        for bytes in [Data(), Data([1]), Data([1, 2, 3])] {
            let encoder = try NativeFBXExportEncoder(
                maximumGeometryPayloadBytes: 1024, maximumOutputPayloadBytes: 2,
                operation: RecordedFBXEncoding(.success(.init(bytes: bytes, warning: "keep"))))
            do {
                _ = try await encoder.encode(archive: Data([1]), format: .fbx)
                XCTFail("Invalid copied output must not publish")
            } catch let error as NativeFBXExportError { XCTAssertEqual(error, .invalidNativeOutput) }
        }
    }

    func testSwiftCancellationBeforeAndAfterFakeOperationDoesNotDispatchNativeCancellation() async throws {
        let operation = RecordedFBXEncoding(.success(.init(bytes: Data([1]), warning: "")))
        let encoder = try NativeFBXExportEncoder(
            maximumGeometryPayloadBytes: 1024, maximumOutputPayloadBytes: 1024, operation: operation)
        let before = Task { try await encoder.encode(archive: Data([1]), format: .fbx) }
        before.cancel()
        do {
            _ = try await before.value
            XCTFail("Cancelled work ran")
        } catch is CancellationError {}
        XCTAssertTrue(operation.recorded.isEmpty)
        let cancels = RecordedFBXEncoding(.success(.init(bytes: Data([1]), warning: "")), cancels: true)
        let afterEncoder = try NativeFBXExportEncoder(
            maximumGeometryPayloadBytes: 1024, maximumOutputPayloadBytes: 1024, operation: cancels)
        let after = Task { try await afterEncoder.encode(archive: Data([1]), format: .fbx) }
        do {
            _ = try await after.value
            XCTFail("Cancelled result was returned")
        } catch is CancellationError {}
        XCTAssertEqual(cancels.recorded.count, 1)
    }
}
