import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct QtXMLPasteNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    { throw CancellationError() }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}

private actor HeldQtXMLReader {
    private var result: CheckedContinuation<Data, Never>?
    private var start: CheckedContinuation<Void, Never>?

    func read(_ url: URL) async -> Data {
        await withCheckedContinuation { continuation in
            result = continuation
            start?.resume()
            start = nil
        }
    }

    func waitForRead() async {
        if result != nil { return }
        await withCheckedContinuation { start = $0 }
    }

    func release(_ data: Data) {
        result?.resume(returning: data)
        result = nil
    }
}

@MainActor
final class QtXMLFilePasteStoreTests: XCTestCase {
    func testPickerLeaseRejectsStaleDeliveryAndPublishesOnlyToTheCapturedStore() async throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fragment.xml")
        try source.modelXML.write(to: url)
        let store = makeStore()
        let other = makeStore()
        defer {
            store.stop()
            other.stop()
        }
        XCTAssertFalse(store.canChooseQtXMLFile)
        await store.load(data: source.encoded(), fileIdentity: UUID())
        await other.load(data: source.encoded(), fileIdentity: UUID())
        try await settle(store)
        try await settle(other)
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }

        store.chooseQtXMLFile()
        let stale = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        XCTAssertFalse(store.canChooseQtXMLFile)
        store.selectGraph(nodes: ["a"], edges: [])
        try await settle(store)
        store.finishQtXMLFileChoice(requestID: stale, result: .success([url]))
        XCTAssertNil(store.qtXMLFilePasteRequestID)
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(writes.isEmpty)

        store.chooseQtXMLFile()
        let cancelled = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        store.cancelQtXMLFileChoice(requestID: cancelled)
        store.chooseQtXMLFile()
        let current = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        store.finishQtXMLFileChoice(requestID: cancelled, result: .success([url]))
        XCTAssertEqual(store.qtXMLFilePasteRequestID, current)
        other.finishQtXMLFileChoice(requestID: current, result: .success([url]))
        store.finishQtXMLFileChoice(requestID: current, result: .success([url]))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 2)
        XCTAssertTrue(store.snapshot?.componentTree.rows.allSatisfy { $0.component.parentID == nil } == true)
        XCTAssertEqual(other.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(store.canUndo)

        store.undo()
        try await settle(store)
        XCTAssertEqual(writes.last, source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testXMLPickerCapturesWorkingGroupAndRejectsChangedOrDeletedDestination() async throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let destination = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='working'/></components></canvas>".utf8))
        let url = URL(fileURLWithPath: "/unused/fragment.xml")
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: destination.encoded(), fileIdentity: UUID())
        store.selectComponent("working")
        try await settle(store)
        let selected = try XCTUnwrap(store.snapshot)
        store.workingGroupAction(.group("working"), snapshot: selected)()

        store.chooseQtXMLFile()
        let old = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        store.workingGroupAction(.documentRoot, snapshot: selected)()
        store.workingGroupAction(.group("working"), snapshot: selected)()
        XCTAssertNil(
            store.finishQtXMLFileChoice(requestID: old, result: .success([url]), read: { _ in source.modelXML }))
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.document.encoded(), destination.encoded())
        XCTAssertFalse(store.canUndo)

        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }
        store.chooseQtXMLFile()
        let current = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        let paste = try XCTUnwrap(
            store.finishQtXMLFileChoice(requestID: current, result: .success([url]), read: { _ in source.modelXML }))
        await paste.value
        let part = try XCTUnwrap(store.snapshot?.componentTree.rows.first { $0.component.partID != nil })
        XCTAssertEqual(part.component.parentID, "working")
        XCTAssertEqual(writes.count, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), destination.encoded())
        XCTAssertFalse(store.canUndo)

        store.selectComponent("working")
        try await settle(store)
        let beforeDeletion = try XCTUnwrap(store.snapshot)
        store.chooseQtXMLFile()
        let deleted = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        store.componentDeletionAction(ComponentDeletionTarget(snapshot: beforeDeletion))()
        try await settle(store)
        let afterDeletion = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(store.addPlacementDestination, .documentRoot)
        XCTAssertNil(
            store.finishQtXMLFileChoice(requestID: deleted, result: .success([url]), read: { _ in source.modelXML }))
        XCTAssertEqual(store.snapshot?.document.encoded(), afterDeletion.document.encoded())
        XCTAssertTrue(store.snapshot?.nodes.isEmpty == true)
    }

    func testOldReadCannotPublishIntoReplacementOrEndItsNewOperation() async throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let replacement = Dust3DDocument.emptyArchive()
        let url = URL(fileURLWithPath: "/unused/fragment.xml")
        let store = makeStore()
        defer { store.stop() }
        let original = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='working'/></components></canvas>".utf8))
        await store.load(data: original.encoded(), fileIdentity: UUID())
        let originalSnapshot = try XCTUnwrap(store.snapshot)
        let originalID = originalSnapshot.documentIdentity
        store.workingGroupAction(.group("working"), snapshot: originalSnapshot)()
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }

        let oldReader = HeldQtXMLReader()
        store.chooseQtXMLFile()
        let oldID = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        let oldOperation = try XCTUnwrap(
            store.finishQtXMLFileChoice(requestID: oldID, result: .success([url]), read: oldReader.read))
        await oldReader.waitForRead()

        await store.load(data: replacement, fileIdentity: UUID())
        let replacementID = try XCTUnwrap(store.snapshot?.documentIdentity)
        XCTAssertNotEqual(originalID, replacementID)
        let newReader = HeldQtXMLReader()
        store.chooseQtXMLFile()
        let newID = try XCTUnwrap(store.qtXMLFilePasteRequestID)
        let newOperation = try XCTUnwrap(
            store.finishQtXMLFileChoice(requestID: newID, result: .success([url]), read: newReader.read))
        await newReader.waitForRead()

        await oldReader.release(source.modelXML)
        await oldOperation.value
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.snapshot?.documentIdentity, replacementID)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(writes.isEmpty)

        await newReader.release(Data("<canvas/>".utf8))
        await newOperation.value
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement)
        XCTAssertTrue(writes.isEmpty)
    }

    func testReaderRejectsOversizedAndNonRegularFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversized = directory.appendingPathComponent("oversized.xml")
        try Data().write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 16 * 1024 * 1024 + 1)
        try handle.close()
        let nonRegular = directory.appendingPathComponent("folder.xml")
        try FileManager.default.createDirectory(at: nonRegular, withIntermediateDirectories: false)
        let reader = QtXMLFileReader()
        do {
            _ = try await reader.read(oversized)
            XCTFail("Oversized file read succeeded")
        } catch QtXMLFileReader.Failure.tooLarge {}
        do {
            _ = try await reader.read(nonRegular)
            XCTFail("A directory was admitted as an XML file")
        } catch QtXMLFileReader.Failure.invalidFile {}
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeStore() -> EditorStore {
        let stub = QtXMLPasteNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Qt XML file paste did not settle")
    }
}
