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
    func testPendingImageFitKeepsNodeGestureDisplayProjectionStable() async throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 4, height: 1, bitsPerComponent: 8, bytesPerRow: 16,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let png = try ReferenceImageCodec.encodePNG(image)
        let images = HeldNodeDragReferenceImage(image: image)
        let store = EditorStore(referenceImages: images)
        defer {
            store.stop()
            Task { await images.release() }
        }
        let model = Data(
            "<canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='p'/></parts></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let archive =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        let document = try Dust3DDocument(data: archive).applying(.setReferenceImagePNG(png))
        await store.load(data: document.encoded())
        await images.waitForRequest()
        let snapshot = try XCTUnwrap(store.snapshot)
        let original = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        var lifecycle = NodeDragLifecycle()
        let token = UUID()
        try lifecycle.begin(token: token, anchorID: "a", snapshot: snapshot, projection: original)
        lifecycle.update(token: token, snapshot: snapshot, translation: .init(x: 10, y: 0))
        await images.release()
        try await settle(store)
        let fitted = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        let node = try XCTUnwrap(snapshot.nodes.first)
        XCTAssertNotEqual(original.point(for: node.value.position), fitted.point(for: node.value.position))
        XCTAssertEqual(
            lifecycle.displayProjection(fallback: fitted).point(for: node.value.position),
            original.point(for: node.value.position))
    }

    @MainActor
    func testCompositionCannotReuseCachedImageWhileReplacementDecodeIsPending() async throws {
        let originalPNG = try png()
        let oldImage = try ReferenceImageCodec.decodePNG(originalPNG)
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let newImage = try XCTUnwrap(context.makeImage())
        let replacementPNG = try ReferenceImageCodec.encodePNG(newImage)
        let images = ReplacementReferenceImages(original: oldImage, replacementPNG: replacementPNG)
        let store = EditorStore(referenceImages: images)
        defer {
            store.stop()
            Task { await images.release(newImage) }
        }
        XCTAssertNil(store.referenceImageForComposition)
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .setReferenceImagePNG(originalPNG))
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertTrue(store.referenceImageForComposition === oldImage)
        store.importReferenceImage(from: URL(fileURLWithPath: "/replacement.png"))
        try await settle(store, includingImage: false)
        for _ in 0..<300 {
            if await images.isWaiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let isWaiting = await images.isWaiting
        XCTAssertTrue(isWaiting)
        XCTAssertTrue(store.isLoadingReferenceImage)
        XCTAssertEqual(store.snapshot?.document.referenceImagePNG, replacementPNG)
        XCTAssertTrue(store.referenceImage === oldImage)
        XCTAssertNil(store.referenceImageForComposition)
        await images.release(newImage)
        try await settle(store)
        XCTAssertTrue(store.referenceImageForComposition === newImage)
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

private actor HeldNodeDragReferenceImage: ReferenceImageServing {
    private var pending: CheckedContinuation<ReferenceImagePreview, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private let image: CGImage

    init(image: CGImage) { self.image = image }
    func importImage(url: URL) async throws -> Data { Data() }
    func preview(document: Dust3DDocument) async throws -> ReferenceImagePreview {
        await withCheckedContinuation { continuation in
            pending = continuation
            waiter?.resume()
            waiter = nil
        }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        pending?.resume(returning: .init(image: image, changed: true))
        pending = nil
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

private actor ReplacementReferenceImages: ReferenceImageServing {
    let original: CGImage
    let replacementPNG: Data
    private var requests = 0
    private var pending: CheckedContinuation<ReferenceImagePreview, Never>?
    var isWaiting: Bool { pending != nil }

    init(original: CGImage, replacementPNG: Data) {
        self.original = original
        self.replacementPNG = replacementPNG
    }
    func importImage(url: URL) -> Data { replacementPNG }
    func preview(document: Dust3DDocument) async -> ReferenceImagePreview {
        requests += 1
        if requests == 1 { return .init(image: original, changed: true) }
        return await withCheckedContinuation { pending = $0 }
    }
    func release(_ image: CGImage) {
        pending?.resume(returning: .init(image: image, changed: true))
        pending = nil
    }
}
