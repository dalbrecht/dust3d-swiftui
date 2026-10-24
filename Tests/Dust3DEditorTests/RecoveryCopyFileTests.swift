import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class RecoveryCopyFileTests: XCTestCase {
    func testCancellationKeepsCompletedCopyAndReportsRemainingWindowWithoutChangingOriginal() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try document()
        let first = UUID()
        let second = UUID()
        let writer = EditorRecoveryCopyFileService(
            directory: root,
            writeData: { data, url in
                try data.write(to: url, options: .atomic)
                if url.pathExtension == "ds3" { withUnsafeCurrentTask { $0?.cancel() } }
            })
        let captures: [EditorRecoveryCapture] = [first, second].map {
            .snapshot(.init(documentID: $0, revision: 0, document: source))
        }
        let task = Task { try await writer.write(captures: captures, requestID: UUID()) }
        let report = try await task.value
        XCTAssertEqual(report.copied.count, 1)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(report.failures.first?.cause is CancellationError)
        XCTAssertNil(report.receiptError)
        let copied = try XCTUnwrap(report.copied.first)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(copied.filename)), source.encoded())
        let failed = try XCTUnwrap(report.failures.first?.documentID)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(failed.uuidString.lowercased() + ".ds3").path))
        let receipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("latest-recovery.json")))
                as? [String: Any])
        XCTAssertEqual(receipt["status"] as? String, "partial")
        XCTAssertEqual(source.encoded(), try document().encoded())
    }

    func testNonFileRootAndNonRegularInventoryRejectWithoutFollowingPaths() async throws {
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/recovery"))
        do {
            _ = try await EditorRecoveryCopyFileService(directory: remote).write(captures: [], requestID: UUID())
            XCTFail("Reject a non-file URL before filesystem operations")
        } catch { XCTAssertEqual(error as? EditorRecoveryCopyError, .unsafeLocation) }
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        do {
            _ = try await EditorRecoveryCopyFileService(directory: root).write(captures: [], requestID: UUID())
            XCTFail("Reject nested directories instead of traversing them")
        } catch { XCTAssertEqual(error as? RecoveryCopyPlanError, .invalidInventory) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("nested").path))
    }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "dust3d-recovery-test-\(UUID().uuidString)", isDirectory: true)
    }
    private func document() throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='keep'><nodes/><edges/><parts/><components/><rig future='retain'/></canvas>".utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testEmptyAndFailedReceiptsAreCorrelatedAndDiagnosticsBounded() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = EditorRecoveryCopyFileService(directory: root)
        let request = UUID()
        _ = try await service.write(captures: [], requestID: request)
        let url = root.appendingPathComponent("latest-recovery.json")
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(empty["version"] as? Int, 2)
        XCTAssertEqual(empty["processIdentifier"] as? Int32, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(empty["status"] as? String, "noDocuments")
        XCTAssertEqual(empty["requestID"] as? String, request.uuidString)
        let original = LongRecoveryError()
        let report = try await service.write(
            captures: [.failure(.init(documentID: UUID(), cause: original))], requestID: UUID())
        XCTAssertTrue(report.failures.first?.cause is LongRecoveryError)
        let failed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(failed["status"] as? String, "failed")
        let failures = try XCTUnwrap(failed["failures"] as? [[String: Any]])
        XCTAssertEqual(failures.first?["isTruncated"] as? Bool, true)
        XCTAssertLessThanOrEqual((failures.first?["description"] as? String)?.utf8.count ?? Int.max, 1024)
        for identity: String? in [nil, "other.app", "../other"] {
            do {
                _ = try await EditorRecoveryCopyFileService(bundleIdentifier: identity).write(
                    captures: [], requestID: UUID())
                XCTFail("Reject unsupported app identity before filesystem access")
            } catch { XCTAssertEqual(error as? EditorRecoveryCopyError, .unsafeIdentity) }
        }
    }

    func testWritesExactPrivateCopyReceiptAndStableReplacementWithoutChangingSource() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = EditorRecoveryCopyFileService(directory: root)
        let source = try document()
        let id = UUID()
        let snapshot = EditorRecoverySnapshot(documentID: id, revision: 4, document: source)
        let requestID = UUID()
        let report = try await service.write(captures: [.snapshot(snapshot)], requestID: requestID)
        XCTAssertEqual(report.copied.map(\.revision), [4])
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertNil(report.receiptError)
        let destination = root.appendingPathComponent(snapshot.request.filename)
        XCTAssertEqual(try Data(contentsOf: destination), source.encoded())
        XCTAssertEqual(
            try Dust3DDocument(data: Data(contentsOf: destination)).asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        let receipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("latest-recovery.json")))
                as? [String: Any])
        XCTAssertEqual(receipt["requestID"] as? String, requestID.uuidString)
        XCTAssertEqual(receipt["status"] as? String, "completed")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int, 0o600)
        let changed = try source.applying(.setRigType(.bird))
        _ = try await service.write(
            captures: [.snapshot(.init(documentID: id, revision: 5, document: changed))], requestID: UUID())
        XCTAssertEqual(try Data(contentsOf: destination), changed.encoded())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
        XCTAssertEqual(try source.rigSettings().sourceRigType, nil)
    }

    func testIndividualAndReceiptFailuresRetainOriginalCausesAndDoNotBlockOtherCopies() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let failedID = UUID()
        let copiedID = UUID()
        let source = try document()
        let service = EditorRecoveryCopyFileService(
            directory: root,
            writeData: { data, url in
                if url.lastPathComponent == failedID.uuidString.lowercased() + ".ds3" { throw CopyFixtureError.copy }
                try data.write(to: url, options: .atomic)
            })
        let report = try await service.write(
            captures: [
                .snapshot(.init(documentID: failedID, revision: 0, document: source)),
                .snapshot(.init(documentID: copiedID, revision: 0, document: source)),
                .failure(.init(documentID: UUID(), cause: CopyFixtureError.capture)),
            ], requestID: UUID())
        XCTAssertEqual(report.copied.map(\.documentID), [copiedID])
        XCTAssertEqual(report.failures.first(where: { $0.documentID == failedID })?.cause as? CopyFixtureError, .copy)
        XCTAssertEqual(report.failures.count, 2)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent(copiedID.uuidString.lowercased() + ".ds3")),
            source.encoded())
        let receiptFailureService = EditorRecoveryCopyFileService(
            directory: root,
            writeData: { data, url in
                if url.lastPathComponent == "latest-recovery.json" { throw CopyFixtureError.receipt }
                try data.write(to: url, options: .atomic)
            })
        let result = try await receiptFailureService.write(
            captures: [.snapshot(.init(documentID: copiedID, revision: 1, document: source))], requestID: UUID())
        XCTAssertEqual(result.copied.count, 1)
        XCTAssertEqual(result.receiptError as? CopyFixtureError, .receipt)
    }

    func testPrivateDirectoryRejectsSymlinkAndQuotaBeforeChangingRetainedFiles() async throws {
        let parent = directory()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("copies")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let retained = root.appendingPathComponent("retained.bin")
        try Data([1]).write(to: retained)
        let source = try document()
        let capture = EditorRecoveryCapture.snapshot(.init(documentID: UUID(), revision: 0, document: source))
        let service = EditorRecoveryCopyFileService(directory: root, maximumBytes: source.encoded().count)
        do {
            _ = try await service.write(captures: [capture], requestID: UUID())
            XCTFail("Reject the admitted-byte excess before writing")
        } catch { XCTAssertEqual(error as? RecoveryCopyPlanError, .storageLimitExceeded) }
        XCTAssertEqual(try Data(contentsOf: retained), Data([1]))
        let linked = parent.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: root)
        do {
            _ = try await EditorRecoveryCopyFileService(directory: linked).write(captures: [capture], requestID: UUID())
            XCTFail("Do not follow a recovery-root symlink")
        } catch { XCTAssertEqual(error as? EditorRecoveryCopyError, .unsafeLocation) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.ds3"), withDestinationURL: retained)
        do {
            _ = try await EditorRecoveryCopyFileService(directory: root).write(captures: [capture], requestID: UUID())
            XCTFail("Do not follow an inventory symlink")
        } catch { XCTAssertEqual(error as? RecoveryCopyPlanError, .invalidInventory) }
        XCTAssertEqual(try Data(contentsOf: retained), Data([1]))
    }
}

private enum CopyFixtureError: Error, Equatable { case copy, capture, receipt }

private struct LongRecoveryError: Error, CustomStringConvertible {
    var description: String { String(repeating: "x", count: 2048) }
}
