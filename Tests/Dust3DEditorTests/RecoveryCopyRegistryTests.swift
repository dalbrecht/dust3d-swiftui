import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class RecoveryCopyRegistryTests: XCTestCase {
    @MainActor func testOverlappingRecoveryRejectsBeforeCaptureAndWriterFailureAllowsRetry() async throws {
        let writer = HoldingRecoveryWriter()
        let registry = EditorRecoveryCopyRegistry(writer: writer)
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let id = UUID()
        var captures = 0
        registry.register(id) {
            captures += 1
            return EditorRecoverySnapshot(documentID: id, revision: 0, document: document)
        }
        let first = Task { try await registry.recover(requestID: UUID()) }
        await writer.waitUntilEntered()
        do {
            _ = try await registry.recover(requestID: UUID())
            XCTFail("A pending writer must not admit another capture")
        } catch { XCTAssertEqual(error as? EditorRecoveryCopyError, .alreadyWriting) }
        XCTAssertEqual(captures, 1)
        await writer.release()
        do {
            _ = try await first.value
            XCTFail("Preserve the original writer cause")
        } catch { XCTAssertEqual(error as? RecoveryFixtureError, .writer) }
        let retryID = UUID()
        let retry = try await registry.recover(requestID: retryID)
        XCTAssertEqual(retry.requestID, retryID)
        XCTAssertEqual(captures, 2)
    }
    @MainActor func testCaptureUsesLatestHandlerIsolatesOriginalErrorsAndUnregisters() async throws {
        let writer = RecordingRecoveryWriter()
        let registry = EditorRecoveryCopyRegistry(writer: writer)
        let first = UUID()
        let second = UUID()
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        registry.register(first) { throw RecoveryFixtureError.replaced }
        registry.register(first) { EditorRecoverySnapshot(documentID: first, revision: 7, document: document) }
        registry.register(second) { throw RecoveryFixtureError.busyWindow }
        let request = UUID()
        let report = try await registry.recover(requestID: request)
        XCTAssertEqual(report.requestID, request)
        XCTAssertEqual(report.copied.map(\.documentID), [first])
        XCTAssertEqual(report.failures.first?.documentID, second)
        XCTAssertEqual(report.failures.first?.cause as? RecoveryFixtureError, .busyWindow)
        registry.unregister(first)
        registry.unregister(first)
        registry.unregister(second)
        let empty = try await registry.recover(requestID: UUID())
        XCTAssertTrue(empty.copied.isEmpty)
        XCTAssertTrue(empty.failures.isEmpty)
    }

    @MainActor func testIdentityMismatchAndTooManyWindowsRejectBeforeWriting() async throws {
        let writer = RecordingRecoveryWriter()
        let registry = EditorRecoveryCopyRegistry(writer: writer)
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let id = UUID()
        registry.register(id) { EditorRecoverySnapshot(documentID: UUID(), revision: 0, document: document) }
        let invalid = try await registry.recover(requestID: UUID())
        XCTAssertEqual(invalid.failures.first?.cause as? EditorRecoveryCopyError, .identityMismatch)
        for _ in 0..<16 {
            registry.register(UUID()) { throw RecoveryFixtureError.shouldNotCapture }
        }
        do {
            _ = try await registry.recover(requestID: UUID())
            XCTFail("Reject excessive open-window metadata")
        } catch { XCTAssertEqual(error as? RecoveryCopyPlanError, .tooManyDocuments) }
        let calls = await writer.calls
        XCTAssertEqual(calls, 1)
    }

    func testRequestGateAdmitsOnePendingOperationAndReopensAfterCompletion() {
        let gate = EditorRecoveryRequestGate()
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        gate.finish()
        XCTAssertTrue(gate.begin())
        gate.finish()
    }

    func testNotificationAcceptsOnlyBoundedRequestIdentityForItsOwnBundle() {
        let name = EditorRecoveryCopyChannel.notification
        let id = UUID()
        let valid = Notification(
            name: name, object: "org.dust3d.editor.combine-qa", userInfo: ["requestID": id.uuidString])
        XCTAssertEqual(EditorRecoveryCopyChannel.requestID(valid, bundleIdentifier: "org.dust3d.editor.combine-qa"), id)
        XCTAssertNil(EditorRecoveryCopyChannel.requestID(valid, bundleIdentifier: "org.dust3d.editor"))
        XCTAssertNil(EditorRecoveryCopyChannel.requestID(valid, bundleIdentifier: nil))
        for info: [AnyHashable: Any]? in [
            nil, [:], ["requestID": "bad"], ["requestID": id.uuidString, "path": "/tmp/ignored"], ["requestID": 7],
        ] {
            XCTAssertNil(
                EditorRecoveryCopyChannel.requestID(
                    Notification(name: name, object: "org.dust3d.editor.combine-qa", userInfo: info),
                    bundleIdentifier: "org.dust3d.editor.combine-qa"))
        }
    }
}

private enum RecoveryFixtureError: Error { case replaced, busyWindow, shouldNotCapture, writer }

private actor HoldingRecoveryWriter: EditorRecoveryCopyWriting {
    private var hasEntered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func write(captures: [EditorRecoveryCapture], requestID: UUID) async throws -> EditorRecoveryReport {
        if !hasEntered {
            hasEntered = true
            entryWaiter?.resume()
            entryWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
            throw RecoveryFixtureError.writer
        }
        return .init(requestID: requestID, requestedCount: captures.count)
    }
}

private actor RecordingRecoveryWriter: EditorRecoveryCopyWriting {
    private(set) var calls = 0
    func write(captures: [EditorRecoveryCapture], requestID: UUID) async throws -> EditorRecoveryReport {
        calls += 1
        var report = EditorRecoveryReport(requestID: requestID, requestedCount: captures.count)
        for capture in captures {
            switch capture {
            case .snapshot(let snapshot): report.copied.append(snapshot.request)
            case .failure(let failure): report.failures.append(failure)
            }
        }
        return report
    }
}
