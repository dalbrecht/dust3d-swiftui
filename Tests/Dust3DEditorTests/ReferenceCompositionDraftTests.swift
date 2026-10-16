import CoreGraphics
import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

final class ReferenceCompositionDraftTests: XCTestCase {
    private func source() throws -> ReferenceCompositionSource {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 16,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        return try ReferenceCompositionSource(image: image, crop: .init(size: .init(width: 4, height: 2)))
    }
    @MainActor private func settle(_ draft: ReferenceCompositionDraft) async throws {
        for _ in 0..<300 {
            if !draft.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Composition draft did not settle")
    }
    @MainActor func testDraftCropMirrorSwapAndInvalidInputNeverMutateDocument() async throws {
        let input = try source()
        let draft = ReferenceCompositionDraft(service: ImmediateCompositionService(source: input))
        defer { draft.stop() }
        XCTAssertNil(draft.result)
        draft.importSource(url: URL(fileURLWithPath: "/unused"), profile: .front)
        try await settle(draft)
        XCTAssertNotNil(draft.result)
        XCTAssertEqual(draft.front?.crop, input.crop)
        XCTAssertTrue(draft.canApply)
        let gesture = UUID()
        draft.setCropping(gesture, isActive: true)
        XCTAssertFalse(draft.canApply)
        draft.setCropping(gesture, isActive: false)
        XCTAssertTrue(draft.canApply)
        draft.setCrop(profile: .front, values: ["1", "0", "2", "2"])
        try await settle(draft)
        XCTAssertEqual(draft.front?.crop.x, 1)
        draft.swapProfiles()
        try await settle(draft)
        XCTAssertNil(draft.front)
        XCTAssertEqual(draft.side?.crop.x, 1)
        draft.toggleSideMirror()
        try await settle(draft)
        XCTAssertEqual(draft.side?.isMirrored, true)
        draft.setCrop(profile: .side, values: ["0", "0", "1", "2"])
        try await settle(draft)
        XCTAssertEqual(draft.side?.crop.x, 3)
        draft.setCrop(profile: .side, values: ["bad", "0", "1", "2"])
        XCTAssertNil(draft.result)
        XCTAssertNotNil(draft.errorMessage)
        draft.setCrop(profile: .side, values: ["0", "0", "1", "2"])
        try await settle(draft)
        XCTAssertNotNil(draft.result)
        XCTAssertNil(draft.errorMessage)
        draft.remove(.side)
        XCTAssertNil(draft.result)
        XCTAssertNil(draft.side)
    }
    @MainActor func testSourceActionsResetInvalidFieldsAndStalePointerDoesNotOverwriteNewCrop() async throws {
        let input = try source()
        let draft = ReferenceCompositionDraft(service: ImmediateCompositionService(source: input))
        defer { draft.stop() }
        draft.useExisting(input.image)
        try await settle(draft)
        let epoch = draft.sourceEpoch
        draft.setCrop(profile: .front, values: ["bad", "0", "4", "2"])
        XCTAssertNil(draft.result)
        draft.useExisting(input.image)
        try await settle(draft)
        XCTAssertGreaterThan(draft.sourceEpoch, epoch)
        XCTAssertNil(draft.errorMessage)
        draft.setCrop(profile: .front, values: ["1", "0", "2", "2"])
        try await settle(draft)
        let changed = try XCTUnwrap(draft.front)
        draft.setPointerCrop(.init(size: input.crop.size), profile: .front, expectedSource: input)
        XCTAssertEqual(draft.front?.crop, changed.crop)
        let displayed = try ReferenceImageCrop(size: input.crop.size, x: 2, y: 0, width: 1, height: 2)
        draft.setPointerCrop(displayed, profile: .front, expectedSource: changed)
        try await settle(draft)
        XCTAssertEqual(draft.front?.crop, displayed)
        draft.setCrop(profile: .front, values: ["bad", "0", "1", "2"])
        let resetEpoch = draft.sourceEpoch
        draft.useFullImage(.front)
        try await settle(draft)
        XCTAssertGreaterThan(draft.sourceEpoch, resetEpoch)
        XCTAssertEqual(draft.front?.crop, input.crop)
        draft.setCrop(profile: .front, values: ["2", "0", "1", "2"])
        try await settle(draft)
        draft.importSource(url: URL(fileURLWithPath: "/invalid"), profile: .side)
        try await settle(draft)
        XCTAssertTrue(draft.errorMessage?.contains("fixture read failure") == true)
        XCTAssertNil(draft.side)
        XCTAssertEqual(draft.front?.crop, displayed)
    }

    @MainActor func testFailedReplacementOrSecondProfileImportRetainsApplicablePreview() async throws {
        let input = try source()
        for profile in ReferenceProfile.allCases {
            let draft = ReferenceCompositionDraft(service: ImmediateCompositionService(source: input))
            defer { draft.stop() }
            draft.useExisting(input.image)
            try await settle(draft)
            let png = try XCTUnwrap(draft.result?.png)
            draft.importSource(url: URL(fileURLWithPath: "/invalid"), profile: profile)
            XCTAssertFalse(draft.canApply)
            XCTAssertEqual(draft.result?.png, png)
            try await settle(draft)
            XCTAssertEqual(draft.result?.png, png)
            XCTAssertTrue(draft.canApply)
            XCTAssertEqual(draft.front?.crop, input.crop)
            XCTAssertNil(draft.side)
            XCTAssertTrue(draft.errorMessage?.contains("fixture read failure") == true)
            draft.setCrop(profile: .front, values: ["bad", "0", "4", "2"])
            draft.importSource(url: URL(fileURLWithPath: "/invalid"), profile: profile)
            try await settle(draft)
            XCTAssertNil(draft.result)
            XCTAssertFalse(draft.canApply)
        }
    }

    @MainActor func testPickerFailurePreservesApplicableDraftAndCannotValidateInvalidCrop() async throws {
        let input = try source()
        let draft = ReferenceCompositionDraft(service: ImmediateCompositionService(source: input))
        draft.useExisting(input.image)
        try await settle(draft)
        let png = try XCTUnwrap(draft.result?.png)
        let epoch = draft.sourceEpoch
        draft.reportImportFailure(ReferenceImageError.fileReadFailed("provider item unavailable"))
        XCTAssertEqual(draft.result?.png, png)
        XCTAssertTrue(draft.canApply)
        XCTAssertEqual(draft.sourceEpoch, epoch)
        XCTAssertTrue(draft.errorMessage?.contains("provider item unavailable") == true)
        draft.setCrop(profile: .front, values: ["bad", "0", "4", "2"])
        draft.reportImportFailure(ReferenceImageError.fileReadFailed("provider unavailable again"))
        XCTAssertNil(draft.result)
        XCTAssertFalse(draft.canApply)
        draft.stop()
        draft.reportImportFailure(ReferenceImageError.invalidImage)
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor func testObsoletePreviewCannotReplaceNewerDraft() async throws {
        let input = try source()
        let service = HeldPreviewCompositionService()
        let draft = ReferenceCompositionDraft(service: service)
        defer { draft.stop() }
        draft.useExisting(input.image)
        for _ in 0..<300 {
            if await service.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        draft.setCrop(profile: .front, values: ["1", "0", "2", "2"])
        for _ in 0..<300 {
            if await service.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let count = await service.count
        XCTAssertEqual(count, 2)
        try await service.releaseFirst()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(draft.result)
        XCTAssertTrue(draft.isWorking)
        try await service.releaseFirst()
        try await settle(draft)
        XCTAssertEqual(draft.result?.layout.width, 1024)
    }

    @MainActor func testStoppedDraftIgnoresLateImportAndCannotRestart() async throws {
        let service = HeldCompositionService(source: try source())
        let draft = ReferenceCompositionDraft(service: service)
        draft.importSource(url: URL(fileURLWithPath: "/unused"), profile: .front)
        for _ in 0..<300 {
            if await service.isWaiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let isWaiting = await service.isWaiting
        XCTAssertTrue(isWaiting)
        draft.stop()
        await service.release()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(draft.front)
        XCTAssertNil(draft.result)
        XCTAssertFalse(draft.isWorking)
        XCTAssertFalse(draft.canApply)
        draft.importSource(url: URL(fileURLWithPath: "/unused"), profile: .side)
        XCTAssertFalse(draft.isWorking)
    }
}

private actor ImmediateCompositionService: ReferenceCompositionServing {
    let source: ReferenceCompositionSource
    init(source: ReferenceCompositionSource) { self.source = source }
    func importSource(url: URL) throws -> ReferenceCompositionSource {
        if url.lastPathComponent == "invalid" { throw ReferenceImageError.fileReadFailed("fixture read failure") }
        return source
    }
    func compose(front: ReferenceCompositionSource?, side: ReferenceCompositionSource?) throws
        -> ReferenceCompositionResult
    {
        try ReferenceCompositionRaster.compose(front: front, side: side)
    }
}
private actor HeldCompositionService: ReferenceCompositionServing {
    let source: ReferenceCompositionSource
    private var continuation: CheckedContinuation<ReferenceCompositionSource, Never>?
    var isWaiting: Bool { continuation != nil }
    init(source: ReferenceCompositionSource) { self.source = source }
    func importSource(url: URL) async -> ReferenceCompositionSource {
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: source)
        continuation = nil
    }
    func compose(front: ReferenceCompositionSource?, side: ReferenceCompositionSource?) throws
        -> ReferenceCompositionResult
    {
        try ReferenceCompositionRaster.compose(front: front, side: side)
    }
}

private actor HeldPreviewCompositionService: ReferenceCompositionServing {
    private var pending:
        [(
            ReferenceCompositionSource?, ReferenceCompositionSource?,
            CheckedContinuation<ReferenceCompositionResult, Never>
        )] = []
    var count: Int { pending.count }
    func importSource(url: URL) throws -> ReferenceCompositionSource { throw ReferenceImageError.invalidImage }
    func compose(front: ReferenceCompositionSource?, side: ReferenceCompositionSource?) async
        -> ReferenceCompositionResult
    {
        await withCheckedContinuation { pending.append((front, side, $0)) }
    }
    func releaseFirst() throws {
        guard !pending.isEmpty else { throw ReferenceImageError.invalidImage }
        let item = pending.removeFirst()
        item.2.resume(returning: try ReferenceCompositionRaster.compose(front: item.0, side: item.1))
    }
}
