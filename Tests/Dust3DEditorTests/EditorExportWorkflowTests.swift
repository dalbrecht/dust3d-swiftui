import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private enum WorkflowExportCause: LocalizedError {
    case encoding
    var errorDescription: String? { "Original export fixture cause" }
}

private actor WorkflowExportEncoder: DocumentExportEncoding {
    private(set) var received: Data?
    private let suspended: Bool
    private let failure: WorkflowExportCause?
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    init(suspended: Bool = false, failure: WorkflowExportCause? = nil) {
        self.suspended = suspended
        self.failure = failure
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        received = archive
        started = true
        startWaiter?.resume()
        startWaiter = nil
        if suspended { await withCheckedContinuation { releaseWaiter = $0 } }
        if let failure { throw failure }
        return .init(bytes: Data("owned export".utf8), warning: "original export warning")
    }
}

private struct WorkflowNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor
final class EditorExportWorkflowTests: XCTestCase {
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Editor command did not settle")
    }

    func testDefaultCapabilityAndFailedReplacementNeverExportRetainedPreviewState() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        defer { try? FileManager.default.removeItem(at: destination) }
        let unbound = EditorStore(preview: WorkflowNoPreview())
        defer { unbound.stop() }
        await unbound.load(data: Dust3DDocument.emptyArchive())
        XCTAssertFalse(unbound.canExport)
        do {
            _ = try await unbound.exportDocument(format: .obj, to: destination, sourceURL: nil)
            XCTFail("No native export encoder is bound by default")
        } catch { XCTAssertEqual(error as? EditorExportWorkflowError, .unavailable) }
        let encoder = WorkflowExportEncoder()
        let store = EditorStore(
            preview: WorkflowNoPreview(), exportService: DocumentExportFileService(encoder: encoder))
        defer { store.stop() }
        await store.load(data: Dust3DDocument.emptyArchive())
        XCTAssertTrue(store.canExport)
        let retained = store.snapshot?.document.encoded()
        await store.load(data: Data())
        XCTAssertEqual(store.snapshot?.document.encoded(), retained)
        XCTAssertFalse(store.canExport)
        do {
            _ = try await store.exportDocument(format: .obj, to: destination, sourceURL: nil)
            XCTFail("A failed replacement must preserve its cause and reject retained-state export")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidArchive) }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDestinationDialogTargetRejectsLaterRevisionBeforeEncodingOrPublication() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        let previous = Data("previous export".utf8)
        try previous.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let encoder = WorkflowExportEncoder()
        let store = EditorStore(
            preview: WorkflowNoPreview(), exportService: DocumentExportFileService(encoder: encoder))
        defer { store.stop() }
        await store.load(data: Dust3DDocument.emptyArchive())
        let captured = EditorExportTarget(snapshot: try XCTUnwrap(store.snapshot))
        store.setOrigin(x: "1", y: "2", z: "3")
        try await settle(store)
        do {
            _ = try await store.exportDocument(format: .obj, to: destination, sourceURL: nil, capturedTarget: captured)
            XCTFail("Choosing a destination cannot silently retarget an earlier export intent")
        } catch { XCTAssertEqual(error as? EditorError, .staleExport) }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        XCTAssertTrue(store.canUndo)
    }

    func testUnsavedExportCapturesRevisionAndPreservesHistoryAndSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.ds3")
        let destination = directory.appendingPathComponent("output.obj")
        let original = Dust3DDocument.emptyArchive()
        try original.write(to: source)
        let encoder = WorkflowExportEncoder(suspended: true)
        let store = EditorStore(
            preview: WorkflowNoPreview(), exportService: DocumentExportFileService(encoder: encoder))
        defer { store.stop() }
        await store.load(data: original)
        store.setOrigin(x: "1", y: "2", z: "3")
        try await settle(store)
        let captured = try XCTUnwrap(store.snapshot)
        XCTAssertNotEqual(captured.document.encoded(), original)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        let operation = Task { try await store.exportDocument(format: .obj, to: destination, sourceURL: source) }
        await encoder.waitUntilStarted()
        XCTAssertTrue(store.isWorking)
        XCTAssertFalse(store.canExport)
        XCTAssertFalse(store.canSave)
        do {
            _ = try await store.exportDocument(format: .obj, to: destination, sourceURL: source)
            XCTFail("A second export must not queue behind the first")
        } catch { XCTAssertEqual(error as? EditorExportWorkflowError, .notReady) }
        store.undo()
        XCTAssertEqual(store.snapshot?.document.encoded(), captured.document.encoded())
        await encoder.release()
        let receipt = try await operation.value
        XCTAssertEqual(receipt.documentIdentity, captured.documentIdentity)
        XCTAssertEqual(receipt.documentRevision, captured.documentRevision)
        XCTAssertEqual(receipt.warning, "original export warning")
        XCTAssertEqual(receipt.byteCount, try Data(contentsOf: destination).count)
        XCTAssertEqual(receipt.destination, destination)
        XCTAssertEqual(receipt.format, .obj)
        let received = await encoder.received
        XCTAssertEqual(received, captured.document.encoded())
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(publications, 0)
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.canExport)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }

    func testCallerCancellationReleasesBarrierAndKeepsExistingOutput() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        let previous = Data("previous export".utf8)
        try previous.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let encoder = WorkflowExportEncoder(suspended: true)
        let store = EditorStore(
            preview: WorkflowNoPreview(), exportService: DocumentExportFileService(encoder: encoder))
        defer { store.stop() }
        await store.load(data: Dust3DDocument.emptyArchive())
        let original = store.snapshot?.document.encoded()
        let operation = Task { try await store.exportDocument(format: .obj, to: destination, sourceURL: nil) }
        await encoder.waitUntilStarted()
        operation.cancel()
        await encoder.release()
        do {
            _ = try await operation.value
            XCTFail("Caller cancellation must reach the owned export task")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(store.canExport)
    }

    func testOriginalEncoderFailureReleasesBarrierWithoutPublishingOrChangingHistory() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        let previous = Data("previous export".utf8)
        try previous.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let encoder = WorkflowExportEncoder(failure: .encoding)
        let store = EditorStore(
            preview: WorkflowNoPreview(), exportService: DocumentExportFileService(encoder: encoder))
        defer { store.stop() }
        do {
            _ = try await store.exportDocument(format: .obj, to: destination, sourceURL: nil)
            XCTFail("An unloaded store cannot export")
        } catch { XCTAssertEqual(error as? EditorExportWorkflowError, .notReady) }
        await store.load(data: Dust3DDocument.emptyArchive())
        let original = store.snapshot?.document.encoded()
        do {
            _ = try await store.exportDocument(format: .obj, to: destination, sourceURL: nil)
            XCTFail("Original encoding failure must propagate")
        } catch { XCTAssertEqual(error as? WorkflowExportCause, .encoding) }
        XCTAssertEqual(store.errorMessage, WorkflowExportCause.encoding.localizedDescription)
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(store.canExport)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(EditorExportWorkflowError.notReady.localizedDescription.isEmpty)
        XCTAssertFalse(EditorExportWorkflowError.unavailable.localizedDescription.isEmpty)
    }

    func testReloadAndStopCancelUncommittedExportsWithoutTouchingOutput() async throws {
        for shouldStop in [false, true] {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
            let previous = Data("previous export".utf8)
            try previous.write(to: destination)
            defer { try? FileManager.default.removeItem(at: destination) }
            let encoder = WorkflowExportEncoder(suspended: true)
            let store = EditorStore(
                preview: WorkflowNoPreview(), exportService: DocumentExportFileService(encoder: encoder))
            defer { store.stop() }
            await store.load(data: Dust3DDocument.emptyArchive())
            let identity = store.snapshot?.documentIdentity
            let operation = Task { try await store.exportDocument(format: .obj, to: destination, sourceURL: nil) }
            await encoder.waitUntilStarted()
            if shouldStop { store.stop() } else { await store.load(data: Dust3DDocument.emptyArchive()) }
            await encoder.release()
            do {
                _ = try await operation.value
                XCTFail("Lifecycle replacement must cancel an uncommitted export")
            } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(try Data(contentsOf: destination), previous)
            XCTAssertFalse(store.isWorking)
            XCTAssertEqual(store.canExport, !shouldStop)
            if !shouldStop { XCTAssertNotEqual(store.snapshot?.documentIdentity, identity) }
        }
    }
}
