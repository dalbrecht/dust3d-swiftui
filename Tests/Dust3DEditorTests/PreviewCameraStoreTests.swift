import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor final class PreviewCameraStoreTests: XCTestCase {
    func testCameraCommandsAreWindowLocalPresentationAndFitDoesNotChangeTheArchiveOrHistory() async throws {
        let store = EditorStore()
        let other = EditorStore()
        defer {
            store.stop()
            other.stop()
        }
        store.movePreviewCamera(.panRight)
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertFalse(store.canMovePreviewCamera)
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.1))
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertTrue(store.canMovePreviewCamera)
        let revision = store.previewRevision
        let reset = store.cameraReset
        store.movePreviewCamera(.panRight)
        XCTAssertNotNil(store.previewCameraCommand)
        XCTAssertNil(other.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, reset)
        store.fitPreviewCamera()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, reset + 1)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        store.movePreviewCamera(.orbitLeft)
        store.reportPreviewRendererError(
            "Renderer unavailable", attemptID: store.previewRendererAttemptID, revision: store.materialViewportRevision)
        XCTAssertFalse(store.canMovePreviewCamera)
        XCTAssertNil(store.previewCameraCommand)
        let failedReset = store.cameraReset
        store.movePreviewCamera(.zoomIn)
        store.fitPreviewCamera()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, failedReset)
        store.retryPreview()
        XCTAssertTrue(store.canMovePreviewCamera)
        store.movePreviewCamera(.orbitLeft)
        store.selectAllNodes()
        try await settle(store)
        store.deleteSelection()
        try await settle(store)
        XCTAssertFalse(store.canMovePreviewCamera)
        XCTAssertNil(store.previewCameraCommand)
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertNil(store.previewCameraCommand)
        store.movePreviewCamera(.orbitRight)
        store.fit()
        XCTAssertNil(store.previewCameraCommand)
        store.movePreviewCamera(.zoomIn)
        store.stop()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertFalse(store.canMovePreviewCamera)
        let stoppedReset = store.cameraReset
        store.movePreviewCamera(.zoomOut)
        store.fitPreviewCamera()
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, stoppedReset)
    }

    func testDisablingLastContributorRetiresCommandBeforeUndoOrReenablingCreatesAnotherViewport() async throws {
        let source = try cameraDocument()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let reset = store.cameraReset
        store.movePreviewCamera(.panRight)
        store.setPartState("{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", property: .disabled, value: true)
        try await settle(store)
        XCTAssertNil(store.mesh)
        XCTAssertFalse(store.canMovePreviewCamera)
        XCTAssertEqual(store.cameraReset, reset, "A state-only edit must not rely on full Fit to retire a command")
        XCTAssertNil(store.previewCameraCommand)
        store.undo()
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.movePreviewCamera(.orbitLeft)
        store.setPartState("{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", property: .disabled, value: true)
        try await settle(store)
        store.setPartState("{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", property: .disabled, value: false)
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewCameraCommand)
    }

    func testRendererRetryKeepsAcceptedPreviewAndDoesNotRegenerateMesh() async throws {
        let source = try cameraDocument()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let acceptedMesh = try XCTUnwrap(store.mesh)
        XCTAssertNil(store.previewRetryAction())
        let revision = store.previewRevision
        let attemptID = store.previewRendererAttemptID
        let materialRevision = store.materialViewportRevision
        store.reportPreviewRendererError("Obsolete mesh", attemptID: attemptID, revision: materialRevision - 1)
        XCTAssertNil(store.renderError)
        store.reportPreviewRendererError("Renderer unavailable", attemptID: attemptID, revision: materialRevision)
        XCTAssertEqual(store.renderError, "Renderer unavailable")

        var ownsWindow = true
        let retry = try XCTUnwrap(store.previewRetryAction { ownsWindow })
        ownsWindow = false
        retry()
        XCTAssertEqual(store.renderError, "Renderer unavailable")
        XCTAssertEqual(store.previewRendererAttemptID, attemptID)
        ownsWindow = true
        retry()

        XCTAssertNotEqual(store.previewRendererAttemptID, attemptID)
        store.reportPreviewRendererError("Retired renderer", attemptID: attemptID, revision: materialRevision)
        retry()
        XCTAssertNil(store.renderError)
        XCTAssertNil(store.previewRetryAction())
        XCTAssertFalse(store.isGenerating)
        try await settle(store)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(store.mesh?.indices, acceptedMesh.indices)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testSuccessfulEmptyResultRetiresCommandWithoutChangingSourceOrHistory() async throws {
        let source = try cameraDocument()
        let generated = try await MeshGenerationSession().generateSourcedIndexed(data: source.encoded())
        let healthy = EditorPreviewResult(sourced: generated)
        let empty = EditorPreviewResult(
            sourced: SourcedMeshGenerationResult(
                mesh: nil, sourceHints: nil, statistics: generated.statistics))
        let preview = CameraResultPreview(healthy)
        let store = EditorStore(preview: preview)
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        store.movePreviewCamera(.zoomIn)
        let reset = store.cameraReset
        await preview.setResult(empty)
        store.retryPreview()
        try await settle(store)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertEqual(store.cameraReset, reset)
        await preview.setResult(healthy)
        store.retryPreview()
        try await settle(store)
        XCTAssertNotNil(store.mesh)
        XCTAssertNil(store.previewCameraCommand)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
    }

    func testPreviewAppearanceIsWindowLocalAndNeverChangesSourceHistoryOrCamera() async throws {
        let source = try cameraDocument()
        let store = EditorStore()
        let other = EditorStore()
        defer {
            store.stop()
            other.stop()
        }
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertTrue(store.showsPreviewColor)
        let previewRevision = store.previewRevision
        let cameraReset = store.cameraReset
        store.movePreviewCamera(.panLeft)
        let command = store.previewCameraCommand?.id
        store.showsPreviewColor = false
        store.isWireframe = true
        XCTAssertTrue(other.showsPreviewColor)
        XCTAssertFalse(other.isWireframe)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.previewRevision, previewRevision)
        XCTAssertEqual(store.cameraReset, cameraReset)
        XCTAssertEqual(store.previewCameraCommand?.id, command)
        store.showsPreviewColor = true
        XCTAssertFalse(store.canUndo)
    }

    func testAutomaticOrbitIsOptInWindowLocalAndPausesForEmptyOrFailedPreview() async throws {
        let source = try cameraDocument()
        let store = EditorStore()
        let other = EditorStore()
        defer {
            store.stop()
            other.stop()
        }
        XCTAssertFalse(store.automaticallyOrbitsPreview)
        store.automaticallyOrbitsPreview = true
        XCTAssertFalse(store.isPreviewAutomaticallyOrbiting)
        await store.load(data: source.encoded())
        try await settle(store)
        let revision = store.previewRevision
        let reset = store.cameraReset
        XCTAssertTrue(store.isPreviewAutomaticallyOrbiting)
        XCTAssertFalse(other.automaticallyOrbitsPreview)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.previewRevision, revision)
        XCTAssertEqual(store.cameraReset, reset)
        store.reportPreviewRendererError(
            "Renderer unavailable", attemptID: store.previewRendererAttemptID, revision: store.materialViewportRevision)
        XCTAssertFalse(store.isPreviewAutomaticallyOrbiting)
        store.retryPreview()
        XCTAssertTrue(store.isPreviewAutomaticallyOrbiting)
        store.setPartState("{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", property: .disabled, value: true)
        try await settle(store)
        XCTAssertFalse(store.isPreviewAutomaticallyOrbiting)
        store.undo()
        try await settle(store)
        XCTAssertTrue(store.isPreviewAutomaticallyOrbiting)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.stop()
        XCTAssertFalse(store.isPreviewAutomaticallyOrbiting)
    }

    private func cameraDocument() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.1))
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Preview camera source did not settle")
    }
}

private actor CameraResultPreview: EditorPreviewServing {
    private var result: EditorPreviewResult
    init(_ result: EditorPreviewResult) { self.result = result }
    func setResult(_ result: EditorPreviewResult) { self.result = result }
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { result }
    func reset(scopeID: UUID) async throws {}
}
