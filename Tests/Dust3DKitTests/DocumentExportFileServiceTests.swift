import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DKit

private actor RecordingExportEncoder: DocumentExportEncoding {
    private(set) var received: Data?
    private let bytes: Data
    init(bytes: Data = Data("v 0 0 0\nf 1 1 1\n".utf8)) { self.bytes = bytes }
    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        received = archive
        return DocumentExportArtifact(bytes: bytes, warning: "retained diagnostic")
    }
}

private enum ExportFixtureError: Error, Equatable { case encoding }

private struct FailingDocumentExportEncoder: DocumentExportEncoding {
    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        throw ExportFixtureError.encoding
    }
}

private actor SuspendedDocumentExportEncoder: DocumentExportEncoding {
    private var hasStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return DocumentExportArtifact(bytes: Data("owned output".utf8), warning: "retained diagnostic")
    }
}

@MainActor
final class DocumentExportFileServiceTests: XCTestCase {
    func testStaleRevisionAfterEncodingPreservesOutputIncludingEditUndoCycle() async throws {
        let session = EditorSession()
        let snapshot = try await session.open(data: Dust3DDocument.emptyArchive())
        let target = EditorExportTarget(snapshot: snapshot)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        let previous = Data("previous export".utf8)
        try previous.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let encoder = SuspendedDocumentExportEncoder()
        let service = DocumentExportFileService(encoder: encoder)
        let operation = Task {
            try await service.export(
                snapshot.document, format: .obj, to: destination, sourceURL: nil,
                validateSnapshot: { try await session.validateExport(target) })
        }
        await encoder.waitUntilStarted()
        _ = try await session.apply([.setOrigin(.init(x: 1, y: 2, z: 3))])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), snapshot.document.encoded())
        await encoder.release()
        do {
            _ = try await operation.value
            XCTFail("A newer revision must retire output even after Undo restores bytes")
        } catch { XCTAssertEqual(error as? EditorError, .staleExport) }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
    }

    func testReopenedDocumentRejectsOldExportBeforeEncoding() async throws {
        let session = EditorSession()
        let snapshot = try await session.open(data: Dust3DDocument.emptyArchive())
        let target = EditorExportTarget(snapshot: snapshot)
        _ = try await session.open(data: snapshot.document.encoded())
        let encoder = RecordingExportEncoder()
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        defer { try? FileManager.default.removeItem(at: destination) }
        do {
            _ = try await DocumentExportFileService(encoder: encoder).export(
                snapshot.document, format: .obj, to: destination, sourceURL: nil,
                validateSnapshot: { try await session.validateExport(target) })
            XCTFail("Reopen must invalidate a captured target even with the same bytes/revision")
        } catch { XCTAssertEqual(error as? EditorError, .staleExport) }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCurrentExportAdmissionIgnoresTransientLocksAndPreservesDiagnostic() async throws {
        let session = EditorSession()
        let snapshot = try await session.open(data: Dust3DDocument.emptyArchive())
        let target = EditorExportTarget(snapshot: snapshot)
        _ = try await session.setLock(.x, isLocked: true)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        defer { try? FileManager.default.removeItem(at: destination) }
        let artifact = try await DocumentExportFileService(encoder: RecordingExportEncoder()).export(
            snapshot.document, format: .obj, to: destination, sourceURL: nil,
            validateSnapshot: { try await session.validateExport(target) })
        XCTAssertEqual(try Data(contentsOf: destination), artifact.bytes)
        XCTAssertEqual(artifact.warning, "retained diagnostic")
    }

    func testPublishesCapturedDocumentAndPreservesSourceAndDiagnostic() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.ds3")
        let original = Dust3DDocument.emptyArchive()
        try original.write(to: source)
        let destination = directory.appendingPathComponent("output.OBJ")
        try Data("old output".utf8).write(to: destination)
        var history = DocumentHistory(document: try Dust3DDocument(data: original))
        try history.apply(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 1, y: 2, z: 3), radius: 0.2))
        let unsaved = history.document.encoded()
        XCTAssertNotEqual(unsaved, original)
        let encoder = RecordingExportEncoder()
        let receipt = try await DocumentExportFileService(encoder: encoder).export(
            history.document, format: .obj, to: destination, sourceURL: source)
        let received = await encoder.received
        XCTAssertEqual(received, unsaved)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: destination), receipt.bytes)
        XCTAssertEqual(receipt.warning, "retained diagnostic")
        XCTAssertTrue(history.isDirty)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original)
        XCTAssertFalse(history.isDirty)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), unsaved)
        XCTAssertTrue(history.isDirty)
    }

    func testRejectsDestinationAliasingSourceBeforeEncoding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.ds3")
        let target = directory.appendingPathComponent("alias.obj")
        let original = Data("source".utf8)
        try original.write(to: source)
        try FileManager.default.linkItem(at: source, to: target)
        let encoder = RecordingExportEncoder()
        do {
            _ = try await DocumentExportFileService(encoder: encoder).export(
                Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj, to: target, sourceURL: source)
            XCTFail("Source alias accepted")
        } catch {
            XCTAssertEqual(error as? DocumentExportError, .sourceAlias)
        }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testRejectsHardlinkToSourceOpenedThroughSymlinkBeforeEncoding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.ds3")
        let source = directory.appendingPathComponent("opened.ds3")
        let target = directory.appendingPathComponent("alias.obj")
        let bytes = Dust3DDocument.emptyArchive()
        try bytes.write(to: original)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: original)
        try FileManager.default.linkItem(at: original, to: target)
        let encoder = RecordingExportEncoder()
        do {
            _ = try await DocumentExportFileService(encoder: encoder).export(
                Dust3DDocument(data: bytes), format: .obj, to: target, sourceURL: source)
            XCTFail("A hardlink to the resolved source must be rejected")
        } catch {
            XCTAssertEqual(error as? DocumentExportError, .sourceAlias)
        }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testRejectsWrongExtensionAndSymlinkWithoutCallingEncoder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = directory.appendingPathComponent("real.obj")
        try Data("keep".utf8).write(to: real)
        let link = directory.appendingPathComponent("link.obj")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let encoder = RecordingExportEncoder()
        for target in [
            directory.appendingPathComponent("output.ds3"), link, directory.appendingPathComponent("folder.obj"),
        ] {
            if target.lastPathComponent == "folder.obj" {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            }
            do {
                _ = try await DocumentExportFileService(encoder: encoder).export(
                    Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj, to: target, sourceURL: nil)
                XCTFail("Invalid destination accepted")
            } catch { XCTAssertEqual(error as? DocumentExportError, .invalidDestination) }
        }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertEqual(try Data(contentsOf: real), Data("keep".utf8))
    }

    func testEmptyOutputPreservesPreviousFile() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("fbx")
        try Data("keep".utf8).write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }
        do {
            _ = try await DocumentExportFileService(encoder: RecordingExportEncoder(bytes: Data())).export(
                Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .fbx, to: target, sourceURL: nil)
            XCTFail("Empty output accepted")
        } catch { XCTAssertEqual(error as? DocumentExportError, .invalidOutput) }
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }

    func testCreatesNewOutputAndRejectsSameSourcePathAndNondirectoryParent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let target = directory.appendingPathComponent("new.obj")
        let service = DocumentExportFileService(encoder: RecordingExportEncoder())
        let output = try await service.export(document, format: .obj, to: target, sourceURL: nil)
        XCTAssertEqual(try Data(contentsOf: target), output.bytes)
        do {
            _ = try await service.export(document, format: .obj, to: target, sourceURL: target)
            XCTFail("Same source path accepted")
        } catch { XCTAssertEqual(error as? DocumentExportError, .sourceAlias) }
        do {
            _ = try await service.export(
                document, format: .obj, to: target.appendingPathComponent("nested.obj"), sourceURL: nil)
            XCTFail("Nondirectory parent accepted")
        } catch { XCTAssertEqual(error as? DocumentExportError, .invalidDestination) }
        XCTAssertEqual(try Data(contentsOf: target), output.bytes)
    }

    func testEncoderErrorPreservesOriginalCauseAndPreviousOutput() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("obj")
        let original = Data("previous output".utf8)
        try original.write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }
        do {
            _ = try await DocumentExportFileService(encoder: FailingDocumentExportEncoder()).export(
                Dust3DDocument(data: Dust3DDocument.emptyArchive()), format: .obj, to: target, sourceURL: nil)
            XCTFail("Encoder error discarded")
        } catch { XCTAssertEqual(error as? ExportFixtureError, .encoding) }
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testPrecancelledExportDoesNotCallEncoderOrPublish() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("obj")
        let original = Data("previous output".utf8)
        try original.write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }
        let encoder = RecordingExportEncoder()
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let service = DocumentExportFileService(encoder: encoder)
        let operation = Task { try await service.export(document, format: .obj, to: target, sourceURL: nil) }
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Precancelled export published")
        } catch { XCTAssertTrue(error is CancellationError) }
        let received = await encoder.received
        XCTAssertNil(received)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testCancellationDuringEncodingPreservesPreviousOutput() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("obj")
        let original = Data("previous output".utf8)
        try original.write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }
        let encoder = SuspendedDocumentExportEncoder()
        let service = DocumentExportFileService(encoder: encoder)
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let operation = Task { try await service.export(document, format: .obj, to: target, sourceURL: nil) }
        await encoder.waitUntilStarted()
        operation.cancel()
        await encoder.release()
        do {
            _ = try await operation.value
            XCTFail("Cancelled export published")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testRevalidatesSourceInodeAliasAfterEncoding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.ds3")
        let target = directory.appendingPathComponent("output.obj")
        let original = Data("owned source".utf8)
        try original.write(to: source)
        try Data("old output".utf8).write(to: target)
        let encoder = SuspendedDocumentExportEncoder()
        let service = DocumentExportFileService(encoder: encoder)
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let operation = Task { try await service.export(document, format: .obj, to: target, sourceURL: source) }
        await encoder.waitUntilStarted()
        let replacement: Result<Void, any Error>
        do {
            try FileManager.default.removeItem(at: target)
            try FileManager.default.linkItem(at: source, to: target)
            replacement = .success(())
        } catch { replacement = .failure(error) }
        await encoder.release()
        let result = await operation.result
        try replacement.get()
        switch result {
        case .success: XCTFail("Source alias introduced during encoding was replaced")
        case .failure(let error): XCTAssertEqual(error as? DocumentExportError, .sourceAlias)
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

}
