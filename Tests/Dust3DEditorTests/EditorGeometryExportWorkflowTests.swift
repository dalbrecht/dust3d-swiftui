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
    private(set) var receivedFormat: DocumentExportFormat?
    private let suspended: Bool
    private let failure: NativeFBXExportError?
    private var hasStarted = false
    private var start: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    init(suspended: Bool = false, failure: NativeFBXExportError? = nil) {
        self.suspended = suspended
        self.failure = failure
    }
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
        receivedFormat = format
        hasStarted = true
        start?.resume()
        start = nil
        if suspended { await withCheckedContinuation { pending = $0 } }
        if let failure { throw failure }
        return .init(bytes: Data("owned OBJ".utf8), warning: "original export warning")
    }
}

@MainActor
private final class DialogChooser: EditorGeometryExportDestinationChoosing {
    private(set) var names: [String] = []
    private(set) var formats: [DocumentExportFormat] = []
    private(set) var cancellationCount = 0
    var failure: NSError?
    private var start: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<URL?, Never>?
    func waitUntilStarted() async {
        if !names.isEmpty { return }
        await withCheckedContinuation { start = $0 }
    }
    func chooseDestination(format: DocumentExportFormat, suggestedName: String) async throws -> URL? {
        names.append(suggestedName)
        formats.append(format)
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
final class EditorGeometryExportWorkflowTests: XCTestCase {
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

    func testFBXAdmissionCausesReachErrorBannerWithoutPublishingOrChangingSource() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let causes: [NativeFBXExportError] = [
            .invalidGeometryBudget(0), .invalidOutputBudget(0), .invalidArchiveByteCount(0),
            .unsupportedFormat(.obj), .invalidNativeOutput,
        ]
        for cause in causes {
            let encoder = DialogEncoder(failure: cause)
            let store = await store(encoder)
            let source = try XCTUnwrap(store.snapshot?.document.encoded())
            let chooser = DialogChooser()
            let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
            let operation = try XCTUnwrap(workflow.begin(format: .fbx, sourceURL: nil))
            await chooser.waitUntilStarted()
            let destination = directory.appendingPathComponent("not-published.fbx")
            chooser.complete(destination)
            let outcome = await operation.value
            XCTAssertThrowsError(try outcome.get()) { XCTAssertEqual($0 as? NativeFBXExportError, cause) }
            XCTAssertEqual(store.errorMessage, cause.localizedDescription)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(store.snapshot?.document.encoded(), source)
            XCTAssertTrue(workflow.canBegin)
            store.stop()
        }
    }

    func testFBXDestinationAndReceiptUseCapturedFormatAndPreserveSource() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        let chooser = DialogChooser()
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
        let destination = directory.appendingPathComponent("out.fbx")
        try Data("old destination".utf8).write(to: destination)
        let operation = try XCTUnwrap(workflow.begin(format: .fbx, sourceURL: nil))
        await chooser.waitUntilStarted()
        XCTAssertEqual(chooser.names, ["Untitled.fbx"])
        XCTAssertEqual(chooser.formats, [.fbx])
        XCTAssertEqual(workflow.format, .fbx)
        XCTAssertNil(workflow.begin(sourceURL: nil))
        chooser.complete(destination)
        let outcome = await operation.value
        let receipt = try XCTUnwrap(try outcome.get())
        XCTAssertEqual(receipt.format, .fbx)
        let receivedFormat = await encoder.receivedFormat
        XCTAssertEqual(receivedFormat, .fbx)
        XCTAssertEqual(try Data(contentsOf: destination), Data("owned OBJ".utf8))
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testFBXChooserCannotPublishAfterSourceReplacement() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
        let destination = directory.appendingPathComponent("keep.fbx")
        let original = Data("keep destination".utf8)
        try original.write(to: destination)
        let operation = try XCTUnwrap(workflow.begin(format: .fbx, sourceURL: nil))
        await chooser.waitUntilStarted()
        await store.load(data: Dust3DDocument.emptyArchive())
        chooser.complete(destination)
        let outcome = await operation.value
        XCTAssertThrowsError(try outcome.get()) { XCTAssertEqual($0 as? EditorError, .staleExport) }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        let received = await encoder.received
        XCTAssertNil(received)
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
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
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
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
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
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
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
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
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
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
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
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
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

    func testShouldRejectCancellationBeforeTaskStartsWithoutPresentingDestination() async throws {
        for retirement in 0..<3 {
            let encoder = DialogEncoder()
            let store = await store(encoder)
            defer { store.stop() }
            let chooser = DialogChooser()
            // Fail immediately if incorrectly invoked, so this regression never opens or hangs a panel.
            chooser.failure = NSError(domain: "UnexpectedExportPresentation", code: 1)
            let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
            let operation = try XCTUnwrap(workflow.begin(sourceURL: nil))
            switch retirement {
            case 0: workflow.cancel()
            case 1: workflow.sourceDidChange()
            default: workflow.stop()
            }
            let outcome = await operation.value
            do {
                _ = try outcome.get()
                XCTFail("Retired intent must not present a chooser")
            } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertTrue(chooser.names.isEmpty)
            let received = await encoder.received
            XCTAssertNil(received)
            XCTAssertNil(store.errorMessage)
            XCTAssertEqual(workflow.canBegin, retirement != 2)
            guard case .idle = workflow.phase else { return XCTFail("Retired task must drain to idle") }
        }
    }

    func testShouldPreserveOriginalChooserFailureAndRemainRetryable() async throws {
        let encoder = DialogEncoder()
        let store = await store(encoder)
        defer { store.stop() }
        let chooser = DialogChooser()
        let original = NSError(
            domain: "ExportDialogFixture", code: 7, userInfo: [NSLocalizedDescriptionKey: "Original chooser cause"])
        chooser.failure = original
        let workflow = EditorGeometryExportWorkflow(store: store, destinations: chooser)
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
