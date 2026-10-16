import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class EditorSaveSnapshotTests: XCTestCase {
    func testNativeSaveSnapshotRejectsPendingEditsAndObsoleteValueCopies() throws {
        let original = Dust3DDocument.emptyArchive()
        var document = try EditorFileDocument(data: original)
        let oldSnapshot = document
        XCTAssertEqual(try document.dataForSaving(), original)
        document.setEditing(true)
        XCTAssertThrowsError(try oldSnapshot.dataForSaving()) {
            XCTAssertEqual($0 as? EditorSaveError, .editInProgress)
        }
        let updated = try Dust3DDocument(data: original).applying(.setOrigin(.init(x: 1, y: 2, z: 3))).encoded()
        document.data = updated
        XCTAssertThrowsError(try document.dataForSaving()) {
            XCTAssertEqual($0 as? EditorSaveError, .editInProgress)
        }
        document.setEditing(false)
        XCTAssertEqual(try document.dataForSaving(), updated)
        XCTAssertThrowsError(try oldSnapshot.dataForSaving()) {
            XCTAssertEqual($0 as? EditorSaveError, .obsoleteSnapshot)
        }
        let undoSnapshot = document
        document.data = original
        XCTAssertThrowsError(try undoSnapshot.dataForSaving()) {
            XCTAssertEqual($0 as? EditorSaveError, .obsoleteSnapshot)
        }
        XCTAssertEqual(try document.dataForSaving(), original)
    }

    func testSeparateDocumentsHaveIndependentSaveStateAndInvalidInputIsRejected() throws {
        let first = EditorFileDocument()
        let second = EditorFileDocument()
        first.setEditing(true)
        XCTAssertThrowsError(try first.dataForSaving())
        XCTAssertNoThrow(try second.dataForSaving())
        first.setEditing(false)
        XCTAssertNoThrow(try first.dataForSaving())
        XCTAssertThrowsError(try EditorFileDocument(data: Data()))
        XCTAssertFalse(EditorSaveError.editInProgress.localizedDescription.isEmpty)
        XCTAssertFalse(EditorSaveError.obsoleteSnapshot.localizedDescription.isEmpty)
    }

    func testNativeErrorsIncludeFailureReasonAndRetryGuidance() {
        for error in [EditorSaveError.editInProgress, .obsoleteSnapshot] {
            let native = error as NSError
            XCTAssertFalse((native.localizedFailureReason ?? "").isEmpty)
            XCTAssertFalse((native.localizedRecoverySuggestion ?? "").isEmpty)
        }
    }

    @MainActor func testStoreSignalsBusyBeforeWorkAndPublishesBeforeReleasingSaveBarrier() async throws {
        let store = EditorStore()
        let observation = SavePublication()
        store.onEditingChanged = { observation.document.setEditing($0) }
        store.onDocumentChanged = { observation.document.data = $0 }
        defer { store.stop() }
        await store.load(data: observation.document.data)
        XCTAssertTrue(store.canSave)
        store.addNode()
        XCTAssertFalse(store.canSave)
        XCTAssertThrowsError(try observation.document.dataForSaving())
        for _ in 0..<300 {
            if !store.isWorking { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let saved = try observation.document.dataForSaving()
        XCTAssertEqual(try Dust3DDocument(data: saved).editorContents().nodes.count, 1)
        store.undo()
        XCTAssertThrowsError(try observation.document.dataForSaving())
        for _ in 0..<300 {
            if !store.isWorking { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(try observation.document.dataForSaving(), Dust3DDocument.emptyArchive())
        store.stop()
        XCTAssertFalse(store.canSave)
    }
    @MainActor func testFailedAndStoppedOperationsReleaseBarrierWithoutPublishingBytes() async throws {
        let images = HeldSaveImport()
        let store = EditorStore(referenceImages: images)
        let observation = SavePublication()
        store.onEditingChanged = { observation.document.setEditing($0) }
        store.onDocumentChanged = { observation.document.data = $0 }
        defer {
            store.stop()
            Task { await images.fail() }
        }
        await store.load(data: observation.document.data)
        for shouldStop in [false, true] {
            store.importReferenceImage(from: URL(fileURLWithPath: "/unused"))
            for _ in 0..<300 {
                if await images.isWaiting { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let isWaiting = await images.isWaiting
            XCTAssertTrue(isWaiting)
            XCTAssertThrowsError(try observation.document.dataForSaving())
            if shouldStop { store.stop() }
            await images.fail()
            for _ in 0..<300 {
                if !store.isWorking { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(try observation.document.dataForSaving(), Dust3DDocument.emptyArchive())
            if !shouldStop { XCTAssertNotNil(store.errorMessage) }
        }
    }
}

@MainActor private final class SavePublication { var document = EditorFileDocument() }

private actor HeldSaveImport: ReferenceImageServing {
    private var pending: CheckedContinuation<Data, any Error>?
    var isWaiting: Bool { pending != nil }
    func preview(document: Dust3DDocument) -> ReferenceImagePreview { .init(image: nil, changed: false) }
    func importImage(url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func fail() {
        pending?.resume(throwing: ReferenceImageError.fileReadFailed("controlled import failure"))
        pending = nil
    }
}
