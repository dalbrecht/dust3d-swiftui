import Dust3DDocument
import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

private actor HistoryPreviewRecorder: EditorPreviewServing {
    private(set) var calls = 0
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        calls += 1
        return EditorPreviewResult(
            sourced: SourcedMeshGenerationResult(
                mesh: nil, sourceHints: nil, statistics: MeshGenerationStatistics(native: Dust3DGenerationStats())))
    }
    func reset(scopeID: UUID) {}
}

private enum PreviewHistoryTestError: Error { case timeout }

private actor DelayedHistoryPreview: EditorPreviewServing {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<EditorPreviewResult, Never>] = [:]

    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        let index = count
        count += 1
        return await withCheckedContinuation { pending[index] = $0 }
    }
    func reset(scopeID: UUID) {}
    func finish(_ index: Int, message: String) {
        pending.removeValue(forKey: index)?.resume(
            returning: EditorPreviewResult(
                ordinary: MeshGenerationResult(
                    mesh: nil, statistics: MeshGenerationStatistics(native: Dust3DGenerationStats())),
                sourceIssue: MeshLoadingError(status: 4, message: message)))
    }
    func finishAll() { for index in Array(pending.keys) { finish(index, message: "cleanup") } }
}

@MainActor
final class PreviewSourceHistoryStoreTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}",
                partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
    }

    func testInFlightGeometrySurvivesAnimationEditUndoAndRedo() async throws {
        let preview = DelayedHistoryPreview()
        let store = EditorStore(preview: preview)
        defer {
            store.stop()
            Task { await preview.finishAll() }
        }
        try await store.load(data: document().encoded())
        try await waitForRequests(1, preview: preview)
        let original = store.generation
        let identity = store.snapshot?.previewIdentity
        store.refreshAnimations()
        await store.animationQuery?.value
        store.createAnimation(name: "Walk", type: "future")
        try await settle(store)
        store.undo()
        try await settle(store)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.previewIdentity, identity)
        XCTAssertEqual(try store.snapshot?.document.animations().count, 1)
        await preview.finish(0, message: "accepted source detail")
        await original?.value
        XCTAssertEqual(store.previewRevision, 1)
        XCTAssertFalse(store.isGenerating)
        XCTAssertEqual(store.previewSourceIssue?.message, "accepted source detail")
        let count = await preview.count
        XCTAssertEqual(count, 1)
    }

    func testReopenWithIdenticalBytesRetiresOldAuxiliaryResult() async throws {
        let preview = DelayedHistoryPreview()
        let store = EditorStore(preview: preview)
        defer {
            store.stop()
            Task { await preview.finishAll() }
        }
        let bytes = try document().encoded()
        await store.load(data: bytes)
        try await waitForRequests(1, preview: preview)
        let old = store.generation
        let oldIdentity = store.snapshot?.previewIdentity
        await store.load(data: bytes)
        try await waitForRequests(2, preview: preview)
        XCTAssertNotEqual(store.snapshot?.previewIdentity, oldIdentity)
        let current = store.generation
        await preview.finish(1, message: "current detail")
        await current?.value
        let revision = store.previewRevision
        await preview.finish(0, message: "obsolete detail")
        await old?.value
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(store.previewSourceIssue?.message, "current detail")
    }

    private func waitForRequests(_ count: Int, preview: DelayedHistoryPreview) async throws {
        for _ in 0..<300 {
            if await preview.count == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Expected \(count) fake preview requests")
        throw PreviewHistoryTestError.timeout
    }

    func testAnimationUndoRedoPreservesPreviewButGeometryHistoryRegenerates() async throws {
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}",
                partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
        let preview = HistoryPreviewRecorder()
        let store = EditorStore(preview: preview)
        defer { store.stop() }
        await store.load(data: source.encoded())
        await store.generation?.value
        store.refreshAnimations()
        await store.animationQuery?.value
        store.createAnimation(name: "Walk", type: "future")
        try await settle(store)
        XCTAssertEqual(try store.snapshot?.document.animations().count, 1)
        store.undo()
        try await settle(store)
        await store.generation?.value
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.redo()
        try await settle(store)
        await store.generation?.value
        XCTAssertEqual(try store.snapshot?.document.animations().count, 1)
        let calls = await preview.calls
        XCTAssertEqual(calls, 1, "Animation-only history must retain the current geometry source")
        store.setOrigin(x: "1", y: "2", z: "3")
        try await settle(store)
        await store.generation?.value
        store.undo()
        try await settle(store)
        await store.generation?.value
        store.redo()
        try await settle(store)
        await store.generation?.value
        let geometryCalls = await preview.calls
        XCTAssertEqual(geometryCalls, 4, "Geometry edits and history must invalidate preview input")
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingAnimations { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Editor operation did not settle")
    }
}
