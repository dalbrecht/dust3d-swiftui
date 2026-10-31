import Foundation
import XCTest

@testable import Dust3DKit

private final class RecordedOBJEncoding: OBJExportOperation, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<DocumentExportArtifact, MeshLoadingError>
    private var calls: [(Data, Int, Bool)] = []
    init(_ result: Result<DocumentExportArtifact, MeshLoadingError>) { self.result = result }
    func encode(archive: Data, maximumOutputPayloadBytes: Int) throws -> DocumentExportArtifact {
        lock.withLock { calls.append((archive, maximumOutputPayloadBytes, Thread.isMainThread)) }
        return try result.get()
    }
    var recorded: [(Data, Int, Bool)] { lock.withLock { calls } }
}

/// Injected operations only. These policy tests never pass fake archive bytes to native code.
@MainActor
final class NativeOBJExportEncoderTests: XCTestCase {
    func testShouldValidateExplicitOutputBudgetBeforeConstructingNativeWork() {
        let operation = RecordedOBJEncoding(.success(.init(bytes: Data([1]), warning: "")))
        for invalid in [-1, 0, 256 * 1024 * 1024 + 1] {
            XCTAssertThrowsError(try NativeOBJExportEncoder(maximumOutputPayloadBytes: invalid, operation: operation)) {
                XCTAssertEqual($0 as? NativeOBJExportError, .invalidOutputBudget(invalid))
            }
        }
        XCTAssertTrue(operation.recorded.isEmpty)
    }
    func testShouldRetainCapturedBytesQuotaAndWarningWhileEncodingOffMainThread() async throws {
        let expected = DocumentExportArtifact(bytes: Data("v 1 2 3\nf 1 2 3\n".utf8), warning: "original warning")
        let operation = RecordedOBJEncoding(.success(expected))
        let encoder = try NativeOBJExportEncoder(maximumOutputPayloadBytes: 1024, operation: operation)
        let archive = Data([1, 2, 3])
        let result = try await encoder.encode(archive: archive, format: .obj)
        XCTAssertEqual(result, expected)
        let call = try XCTUnwrap(operation.recorded.first)
        XCTAssertEqual(operation.recorded.count, 1)
        XCTAssertEqual(call.0, archive)
        XCTAssertEqual(call.1, 1024)
        XCTAssertFalse(call.2)
    }
    func testShouldRejectUnsupportedFormatAndEmptyArchiveWithoutNativeDispatch() async throws {
        let operation = RecordedOBJEncoding(.success(.init(bytes: Data([1]), warning: "")))
        let encoder = try NativeOBJExportEncoder(maximumOutputPayloadBytes: 1024, operation: operation)
        do {
            _ = try await encoder.encode(archive: Data([1]), format: .fbx)
            XCTFail("OBJ encoder must not substitute another format")
        } catch let cause as NativeOBJExportError { XCTAssertEqual(cause, .unsupportedFormat(.fbx)) }
        do {
            _ = try await encoder.encode(archive: Data(), format: .obj)
            XCTFail("Empty input must reject before native work")
        } catch let cause as MeshLoadingError { XCTAssertEqual(cause.status, 1) }
        XCTAssertTrue(operation.recorded.isEmpty)
    }
    func testShouldPreserveOriginalNativeCauseAndRejectInvalidCopiedOutput() async throws {
        let original = MeshLoadingError(status: 3, message: "original native cause")
        let failing = try NativeOBJExportEncoder(
            maximumOutputPayloadBytes: 1024, operation: RecordedOBJEncoding(.failure(original)))
        do {
            _ = try await failing.encode(archive: Data([1]), format: .obj)
            XCTFail("Native failure was hidden")
        } catch let cause as MeshLoadingError {
            XCTAssertEqual(cause.status, original.status)
            XCTAssertEqual(cause.message, original.message)
        }
        for bytes in [Data(), Data([1, 2, 3])] {
            let encoder = try NativeOBJExportEncoder(
                maximumOutputPayloadBytes: 2,
                operation: RecordedOBJEncoding(.success(.init(bytes: bytes, warning: "retained warning"))))
            do {
                _ = try await encoder.encode(archive: Data([1]), format: .obj)
                XCTFail("Invalid output must not reach file publication")
            } catch let cause as NativeOBJExportError { XCTAssertEqual(cause, .invalidNativeOutput) }
        }
    }
}
