import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest
import os

@testable import Dust3DKit

private struct FixedExportEncoder: DocumentExportEncoding {
    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        DocumentExportArtifact(bytes: Data("replacement".utf8), warning: "warning")
    }
}

private struct RedirectingExportCoordinator: DocumentExportCoordinating {
    let admitted: URL
    func coordinate(destination: URL, operation: @escaping DocumentCoordinatedOperation) async throws -> URL {
        try await operation(admitted, {})
        return admitted
    }
}

private actor HeldExportCoordinator: DocumentExportCoordinating {
    private var scheduled = false
    private var scheduleWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func waitForSchedule() async {
        if !scheduled { await withCheckedContinuation { scheduleWaiter = $0 } }
    }
    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
    func coordinate(destination: URL, operation: @escaping DocumentCoordinatedOperation) async throws -> URL {
        scheduled = true
        scheduleWaiter?.resume()
        scheduleWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        try await operation(destination) { try Task.checkCancellation() }
        return destination
    }
}

private final class OwnedReader: Sendable {
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let expired = OSAllocatedUnfairLock(initialState: false)
    func join() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.finished.wait()
                continuation.resume()
            }
        }
    }
}

private struct FailingExportCoordinator: DocumentExportCoordinating {
    let cause: NSError
    func coordinate(destination: URL, operation: @escaping DocumentCoordinatedOperation) async throws -> URL {
        throw cause
    }
}

private enum ExportContext {
    @TaskLocal static var identifier = "missing"
}
private enum ExportContextError: Error { case missing }

@MainActor
final class CoordinatedDocumentExportTests: XCTestCase {
    func testNativeCoordinationRetainsCallingTaskContextThroughPublication() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        defer { try? FileManager.default.removeItem(at: destination) }
        let service = DocumentExportFileService(encoder: FixedExportEncoder())
        let receipt = try await ExportContext.$identifier.withValue("owner") {
            try await service.exportReceipt(
                Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj, to: destination, sourceURL: nil,
                publish: { commit in
                    guard ExportContext.identifier == "owner" else { throw ExportContextError.missing }
                    try commit()
                })
        }
        XCTAssertEqual(receipt.destination, destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("replacement".utf8))
    }

    func testCancellationBeforeCommitPreservesOldBytesAndRemovesStage() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        let previous = Data("old output".utf8)
        try previous.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let staged = OSAllocatedUnfairLock<URL?>(initialState: nil)
        let service = DocumentExportFileService(
            encoder: FixedExportEncoder(), coordinator: NativeDocumentExportCoordinator(),
            didCreateStaging: { url in staged.withLock { $0 = url } })
        let task = Task {
            try await service.exportReceipt(
                Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj, to: destination, sourceURL: nil,
                publish: { commit in
                    withUnsafeCurrentTask { $0?.cancel() }
                    try commit()
                })
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled publication must fail")
        } catch is CancellationError {}
        let directory = try XCTUnwrap(staged.withLock { $0 })
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try Data(contentsOf: destination), previous)
    }

    func testRevisionChangeWhileCoordinationWaitsRejectsPublication() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        let previous = Data("old output".utf8)
        try previous.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let session = EditorSession()
        let snapshot = try await session.open(data: Dust3DDocument.emptyArchive())
        let target = EditorExportTarget(snapshot: snapshot)
        let coordinator = HeldExportCoordinator()
        let service = DocumentExportFileService(encoder: FixedExportEncoder(), coordinator: coordinator)
        let task = Task {
            try await service.exportReceipt(
                snapshot.document, format: .obj, to: destination, sourceURL: nil,
                validateSnapshot: { try await session.validateExport(target) },
                publish: { commit in try await session.publishExport(target, publication: commit) })
        }
        await coordinator.waitForSchedule()
        _ = try await session.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
        _ = try await session.undo()
        await coordinator.release()
        do {
            _ = try await task.value
            XCTFail("Newer revision must reject")
        } catch { XCTAssertEqual(error as? EditorError, .staleExport) }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
    }

    func testCoordinatorFailurePreservesCauseAndOldBytes() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        let previous = Data("old output".utf8)
        try previous.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let cause = NSError(domain: "FixtureCoordinator", code: 47)
        let service = DocumentExportFileService(
            encoder: FixedExportEncoder(), coordinator: FailingExportCoordinator(cause: cause))
        do {
            _ = try await service.exportReceipt(
                Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj, to: destination, sourceURL: nil)
            XCTFail("Coordinator failure must propagate")
        } catch { XCTAssertTrue((error as NSError) === cause) }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
    }

    func testHeldReaderCancellationAndIndependentDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let held = root.appendingPathComponent("held.obj")
        let independent = root.appendingPathComponent("independent.obj")
        let previous = Data("old output".utf8)
        try previous.write(to: held)
        let reader = OwnedReader()
        try await holdReader(at: held, reader: reader)
        defer { reader.release.signal() }
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let (events, scheduled) = AsyncStream<Void>.makeStream()
        var iterator = events.makeAsyncIterator()
        let coordinator = NativeDocumentExportCoordinator(onScheduled: { scheduled.yield(()) })
        let service = DocumentExportFileService(encoder: FixedExportEncoder(), coordinator: coordinator)
        let waiting = Task { try await service.exportReceipt(document, format: .obj, to: held, sourceURL: nil) }
        _ = await iterator.next()
        XCTAssertEqual(try Data(contentsOf: held), previous)
        let other = try await service.exportReceipt(document, format: .obj, to: independent, sourceURL: nil)
        XCTAssertEqual(other.destination, independent)
        let cancelled = expectation(description: "cancelled while reader still holds access")
        let monitor = Task {
            _ = await waiting.result
            cancelled.fulfill()
        }
        waiting.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertFalse(reader.expired.withLock { $0 }, "Reader timed out before cancellation completed")
        XCTAssertEqual(try Data(contentsOf: held), previous)
        reader.release.signal()
        await reader.join()
        _ = await monitor.value
        do {
            _ = try await waiting.value
            XCTFail("Cancelled waiting export must fail")
        } catch is CancellationError {}
        XCTAssertFalse(reader.expired.withLock { $0 })
        XCTAssertEqual(try Data(contentsOf: independent), Data("replacement".utf8))
    }

    func testHeldReaderReleaseAllowsPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("held.obj")
        try Data("old output".utf8).write(to: destination)
        let reader = OwnedReader()
        try await holdReader(at: destination, reader: reader)
        defer { reader.release.signal() }
        let (events, scheduled) = AsyncStream<Void>.makeStream()
        var iterator = events.makeAsyncIterator()
        let service = DocumentExportFileService(
            encoder: FixedExportEncoder(),
            coordinator: NativeDocumentExportCoordinator(onScheduled: { scheduled.yield(()) }))
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let waiting = Task { try await service.exportReceipt(document, format: .obj, to: destination, sourceURL: nil) }
        _ = await iterator.next()
        XCTAssertEqual(try Data(contentsOf: destination), Data("old output".utf8))
        reader.release.signal()
        await reader.join()
        let receipt = try await waiting.value
        XCTAssertFalse(reader.expired.withLock { $0 })
        XCTAssertEqual(receipt.destination, destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("replacement".utf8))
    }

    private func holdReader(at url: URL, reader: OwnedReader) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue(label: "org.dust3d.coordination-test-reader").async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var error: NSError?
                var admitted = false
                coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { _ in
                    admitted = true
                    continuation.resume()
                    if reader.release.wait(timeout: .now() + 10) == .timedOut {
                        reader.expired.withLock { $0 = true }
                    }
                }
                if !admitted { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                reader.finished.signal()
            }
        }
    }

    func testRedirectedDestinationIsWrittenAndReported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let requested = root.appendingPathComponent("requested.obj")
        let admitted = root.appendingPathComponent("admitted.obj")
        let service = DocumentExportFileService(
            encoder: FixedExportEncoder(), coordinator: RedirectingExportCoordinator(admitted: admitted))
        let receipt = try await service.exportReceipt(
            Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj, to: requested, sourceURL: nil)
        XCTAssertEqual(receipt.destination, admitted)
        XCTAssertEqual(try Data(contentsOf: admitted), Data("replacement".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: requested.path))
    }

    func testRedirectedHardLinkToSourceIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.ds3")
        let alias = root.appendingPathComponent("alias.obj")
        let original = Dust3DDocument.emptyArchive()
        try original.write(to: source)
        try FileManager.default.linkItem(at: source, to: alias)
        let service = DocumentExportFileService(
            encoder: FixedExportEncoder(), coordinator: RedirectingExportCoordinator(admitted: alias))
        do {
            _ = try await service.exportReceipt(
                Dust3DDocument(data: original), format: .obj,
                to: root.appendingPathComponent("requested.obj"), sourceURL: source)
            XCTFail("Redirect to a source hard link must fail")
        } catch { XCTAssertEqual(error as? DocumentExportError, .sourceAlias) }
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: alias), original)
    }

    func testRedirectedSourceAliasDoesNotReplaceSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.obj")
        let original = Data("protected".utf8)
        try original.write(to: source)
        let service = DocumentExportFileService(
            encoder: FixedExportEncoder(), coordinator: RedirectingExportCoordinator(admitted: source))
        do {
            _ = try await service.exportReceipt(
                Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj,
                to: root.appendingPathComponent("requested.obj"), sourceURL: source)
            XCTFail("Redirect to source must fail")
        } catch { XCTAssertEqual(error as? DocumentExportError, .sourceAlias) }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
