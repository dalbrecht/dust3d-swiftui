import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct DialogNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

private actor DialogEncoder: DocumentExportEncoding {
    private(set) var received: Data?
    private let suspended: Bool
    private var hasStarted = false
    private var start: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    init(suspended: Bool = false) { self.suspended = suspended }
    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { start = $0 }
    }
    func release() {
        pending?.resume()
        pending = nil
    }
    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        received = archive
        hasStarted = true
        start?.resume()
        start = nil
        if suspended { await withCheckedContinuation { pending = $0 } }
        return .init(bytes: Data("owned OBJ".utf8), warning: "original export warning")
    }
}

@MainActor
private final class DialogChooser: EditorOBJExportDestinationChoosing {
    private(set) var names: [String] = []
    private(set) var cancellationCount = 0
    var failure: NSError?
    private var start: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<URL?, Never>?
    func waitUntilStarted() async {
        if !names.isEmpty { return }
        await withCheckedContinuation { start = $0 }
    }
    func chooseDestination(suggestedName: String) async throws -> URL? {
        names.append(suggestedName)
        start?.resume()
        start = nil
        if let failure { throw failure }
        return await withCheckedContinuation { pending = $0 }
    }
    func complete(_ destination: URL?) {
        pending?.resume(returning: destination)
        pending = nil
    }
    func cancel() {
        cancellationCount += 1
        complete(nil)
    }
}

@MainActor
final class EditorOBJExportWorkflowTests: XCTestCase {
    private func store(_ encoder: DialogEncoder) async -> EditorStore {
        let store = EditorStore(preview: DialogNoPreview(), exportService: DocumentExportFileService(encoder: encoder))
        await store.load(data: Dust3DDocument.emptyArchive())
        return store
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testShouldExportCapturedDocumentThroughChosenDestinationAndPreserveSource() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Example.ds3")
        let archive = Dust3DDocument.emptyArchive()
        try archive.write(to: source)
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let workflow = EditorOBJExportWorkflow(store: store, destinations: chooser)
        let operation = try XCTUnwrap(workflow.begin(sourceURL: source))
        await chooser.waitUntilStarted()
        XCTAssertEqual(chooser.names, ["Example.obj"])
        XCTAssertFalse(workflow.canBegin)
        let destination = directory.appendingPathComponent("result.obj")
        chooser.complete(destination)
        let outcome = await operation.value
        let receipt = try XCTUnwrap(try outcome.get())
        XCTAssertEqual(receipt.destination, destination)
        XCTAssertEqual(receipt.warning, "original export warning")
        guard case .completed(let shown) = workflow.phase else { return XCTFail("Expected published receipt") }
        XCTAssertEqual(shown.documentIdentity, receipt.documentIdentity)
        XCTAssertEqual(try Data(contentsOf: destination), Data("owned OBJ".utf8))
        XCTAssertEqual(try Data(contentsOf: source), archive)
        XCTAssertEqual(store.snapshot?.document.encoded(), archive)
        XCTAssertTrue(workflow.canBegin)
        workflow.dismissResult()
        guard case .idle = workflow.phase else { return XCTFail("Expected dismissed receipt") }
    }

    func testShouldTreatPanelCancellationAsNoExportAndRejectDuplicateDialog() async throws {
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let workflow = EditorOBJExportWorkflow(store: store, destinations: chooser)
        let operation = try XCTUnwrap(workflow.begin(sourceURL: nil))
        await chooser.waitUntilStarted()
        XCTAssertEqual(chooser.names, ["Untitled.obj"])
        XCTAssertNil(workflow.begin(sourceURL: nil))
        chooser.complete(nil)
        let outcome = await operation.value
        XCTAssertNil(try outcome.get())
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertTrue(workflow.canBegin)
        XCTAssertNil(store.errorMessage)
    }

    func testShouldKeepCancellationPendingUntilInjectedEncodingDrainsWithoutPublishing() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result.obj")
        let previous = Data("previous export".utf8)
        try previous.write(to: destination)
        let encoder = DialogEncoder(suspended: true)
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let workflow = EditorOBJExportWorkflow(store: store, destinations: chooser)
        let operation = try XCTUnwrap(workflow.begin(sourceURL: nil))
        await chooser.waitUntilStarted()
        chooser.complete(destination)
        await encoder.waitUntilStarted()
        XCTAssertTrue(workflow.canCancel)
        workflow.cancel()
        XCTAssertFalse(workflow.canCancel)
        workflow.cancel()
        workflow.sourceDidChange()
        XCTAssertEqual(chooser.cancellationCount, 1)
        guard case .cancelling = workflow.phase else { return XCTFail("Must retain cancellation ownership") }
        XCTAssertFalse(workflow.canBegin)
        XCTAssertTrue(store.isWorking)
        XCTAssertNil(workflow.begin(sourceURL: nil))
        await encoder.release()
        let outcome = await operation.value
        do {
            _ = try outcome.get()
            XCTFail("Cancelled export cannot publish")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(workflow.canBegin)
    }

    func testShouldRejectReplacedDocumentAfterDestinationSelectionWithoutNativeEncoding() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result.obj")
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let workflow = EditorOBJExportWorkflow(store: store, destinations: chooser)
        let operation = try XCTUnwrap(workflow.begin(sourceURL: nil))
        await chooser.waitUntilStarted()
        await store.load(data: Dust3DDocument.emptyArchive(), fileIdentity: UUID())
        chooser.complete(destination)
        let outcome = await operation.value
        do {
            _ = try outcome.get()
            XCTFail("Changed source cannot export earlier intent")
        } catch { XCTAssertEqual(error as? EditorError, .staleExport) }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNil(store.errorMessage)
        guard case .idle = workflow.phase else { return XCTFail("No stale error banner") }
    }

    func testShouldStopOwnedDialogWithoutReopeningOrRequestingHumanInput() async throws {
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let workflow = EditorOBJExportWorkflow(store: store, destinations: chooser)
        let operation = try XCTUnwrap(workflow.begin(sourceURL: nil))
        await chooser.waitUntilStarted()
        workflow.stop()
        let outcome = await operation.value
        do {
            _ = try outcome.get()
            XCTFail("Stopped window cannot export")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(chooser.cancellationCount, 1)
        XCTAssertFalse(workflow.canBegin)
        XCTAssertNil(workflow.begin(sourceURL: nil))
        let received = await encoder.received
        XCTAssertNil(received)
    }

    func testShouldForwardRealSourceURLAndRetainOriginalAliasFailure() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Example.ds3")
        let original = Dust3DDocument.emptyArchive()
        try original.write(to: source)
        let alias = directory.appendingPathComponent("alias.obj")
        try FileManager.default.linkItem(at: source, to: alias)
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let workflow = EditorOBJExportWorkflow(store: store, destinations: chooser)
        let operation = try XCTUnwrap(workflow.begin(sourceURL: source))
        await chooser.waitUntilStarted()
        chooser.complete(alias)
        let outcome = await operation.value
        do {
            _ = try outcome.get()
            XCTFail("Source alias cannot be overwritten")
        } catch { XCTAssertEqual(error as? DocumentExportError, .sourceAlias) }
        XCTAssertEqual(try Data(contentsOf: source), original)
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertEqual(store.errorMessage, "Choose an export destination separate from the source document.")
    }

    func testShouldPreserveOriginalChooserFailureAndRemainRetryable() async throws {
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let original = NSError(
            domain: "ExportDialogFixture", code: 7, userInfo: [NSLocalizedDescriptionKey: "Original chooser cause"])
        chooser.failure = original
        let workflow = EditorOBJExportWorkflow(store: store, destinations: chooser)
        let operation = try XCTUnwrap(workflow.begin(sourceURL: nil))
        let outcome = await operation.value
        do {
            _ = try outcome.get()
            XCTFail("Original chooser failure must propagate")
        } catch { XCTAssertTrue(error as NSError === original) }
        XCTAssertEqual(store.errorMessage, "Original chooser cause")
        XCTAssertTrue(workflow.canBegin)
    }
}
