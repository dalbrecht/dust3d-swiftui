import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditor

final class ReferenceImageStoreTests: XCTestCase {
    private func png() throws -> Data {
        try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    }
    @MainActor
    private func waitForImage(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingReferenceImage { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Reference-image operation did not settle")
    }
    @MainActor
    func testImportDisplaySettingsRemovalAndUndoRemainIndependentOfGeometry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reference.png")
        try png().write(to: url)
        let store = EditorStore()
        defer { store.stop() }
        let original = Dust3DDocument.emptyArchive()
        await store.load(data: original)
        try await waitForImage(store)
        store.importReferenceImage(from: url)
        try await waitForImage(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.referenceImageError)
        XCTAssertTrue(store.hasReferenceImage)
        XCTAssertNotNil(store.referenceImage)
        XCTAssertFalse(store.isGenerating)
        XCTAssertTrue(store.snapshot?.nodes.isEmpty == true)
        XCTAssertTrue(store.canUndo)
        let added = try XCTUnwrap(store.snapshot?.document.encoded())
        store.showsReferenceImage = false
        store.referenceImageOpacity = 0.2
        store.fit()
        XCTAssertEqual(store.snapshot?.document.encoded(), added)
        store.removeReferenceImage()
        try await waitForImage(store)
        XCTAssertFalse(store.hasReferenceImage)
        XCTAssertNil(store.referenceImage)
        store.undo()
        try await waitForImage(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), added)
        XCTAssertNotNil(store.referenceImage)
        XCTAssertFalse(store.showsReferenceImage)
        XCTAssertEqual(store.referenceImageOpacity, 0.2)
        store.undo()
        try await waitForImage(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
        store.redo()
        try await waitForImage(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), added)
    }
    @MainActor
    func testInvalidExistingImageIsPreservedAndCanBeRemovedOrUndone() async throws {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .setReferenceImagePNG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: document.encoded())
        try await waitForImage(store)
        XCTAssertTrue(store.hasReferenceImage)
        XCTAssertNil(store.referenceImage)
        XCTAssertNotNil(store.referenceImageError)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
        store.removeReferenceImage()
        try await waitForImage(store)
        XCTAssertFalse(store.hasReferenceImage)
        XCTAssertNil(store.referenceImageError)
        store.undo()
        try await waitForImage(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertNotNil(store.referenceImageError)
    }
    @MainActor
    func testFailedImportPreservesExistingArchiveAndRedo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("invalid.png")
        try Data("invalid".utf8).write(to: url)
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(.setReferenceImagePNG(png()))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: document.encoded())
        try await waitForImage(store)
        store.removeReferenceImage()
        try await waitForImage(store)
        store.undo()
        try await waitForImage(store)
        store.importReferenceImage(from: url)
        try await waitForImage(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertTrue(store.canRedo)
        XCTAssertFalse(store.canUndo)
        XCTAssertNotNil(store.referenceImage)
    }
}
