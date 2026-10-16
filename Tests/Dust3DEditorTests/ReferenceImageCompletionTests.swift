import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class ReferenceImageCompletionTests: XCTestCase {
    private func png() throws -> Data {
        try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    }

    @MainActor
    private func settle(_ store: EditorStore, includingImage: Bool = true) async throws {
        for _ in 0..<300 {
            if !store.isWorking && (!includingImage || !store.isLoadingReferenceImage) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Controlled reference-image operation did not settle")
    }

    @MainActor
    func testDelayedAbsentImageCompletionDoesNotResetCameraAfterOriginEdit() async throws {
        for hadPreviousImage in [false, true] {
            let png = try png()
            let image = hadPreviousImage ? try ReferenceImageCodec.decodePNG(png) : nil
            let images = ControlledReferenceImages(cachedImage: image)
            let store = EditorStore(referenceImages: images)
            defer {
                store.stop()
                Task { await images.release() }
            }
            if hadPreviousImage {
                let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
                    .setReferenceImagePNG(png))
                await store.load(data: document.encoded())
                try await settle(store)
            }
            await store.load(data: Dust3DDocument.emptyArchive())
            await images.waitForRequest()
            XCTAssertTrue(store.isLoadingReferenceImage)
            let camera = store.cameraReset
            store.setOrigin(x: "2", y: "3", z: "4")
            try await settle(store, includingImage: false)
            XCTAssertEqual(store.snapshot?.origin, .init(x: 2, y: 3, z: 4))
            let saved = store.snapshot?.document.encoded()
            store.setMovingOrigin(true)
            let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
            store.updateOriginDrag(translation: .init(x: 10, y: 20), projection: projection)
            let draft = store.originDragPosition
            XCTAssertNotNil(draft)
            await images.release()
            try await settle(store)
            XCTAssertEqual(store.cameraReset, camera)
            XCTAssertTrue(store.isMovingOrigin)
            XCTAssertEqual(store.originDragPosition, draft)
            XCTAssertEqual(store.snapshot?.document.encoded(), saved)
            XCTAssertTrue(store.canUndo)
            XCTAssertNil(store.referenceImage)
            XCTAssertNil(store.referenceImageError)
        }
    }

    @MainActor
    func testRemovalFitsImmediatelyAndCachedUndoRefitsBeforeObsoleteAbsenceCompletes() async throws {
        let png = try png()
        let images = ControlledReferenceImages(cachedImage: try ReferenceImageCodec.decodePNG(png))
        let store = EditorStore(referenceImages: images)
        defer {
            store.stop()
            Task { await images.release() }
        }
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(.setReferenceImagePNG(png))
        await store.load(data: document.encoded())
        try await settle(store)
        let camera = store.cameraReset
        store.removeReferenceImage()
        try await settle(store, includingImage: false)
        await images.waitForRequest()
        XCTAssertNil(store.referenceImage)
        XCTAssertEqual(store.cameraReset, camera + 1)
        store.undo()
        try await settle(store)
        XCTAssertNotNil(store.referenceImage)
        XCTAssertEqual(store.cameraReset, camera + 2)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        await images.release()
    }
}

private actor ControlledReferenceImages: ReferenceImageServing {
    private var pending: CheckedContinuation<ReferenceImagePreview, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private let cachedImage: CGImage?
    private let real = ReferenceImageService()

    init(cachedImage: CGImage?) { self.cachedImage = cachedImage }

    func preview(document: Dust3DDocument) async throws -> ReferenceImagePreview {
        if document.hasReferenceImage { return .init(image: cachedImage, changed: false) }
        return await withCheckedContinuation { continuation in
            pending = continuation
            requestWaiter?.resume()
            requestWaiter = nil
        }
    }

    func importImage(url: URL) async throws -> Data { try await real.importImage(url: url) }

    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func release() {
        pending?.resume(returning: .init(image: nil, changed: cachedImage != nil))
        pending = nil
    }
}
