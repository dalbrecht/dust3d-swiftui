import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class WorkflowReplayWindowTests: XCTestCase {
    func testIndependentRequestsKeepExactSourcesAndClosingOneDoesNotRetireTheOther() throws {
        let windows = WorkflowReplayWindows()
        let first = try document("first")
        let second = try document("second")
        var opened: [UUID] = []
        let firstID = try XCTUnwrap(windows.open(first, deliver: { opened.append($0) }))
        let secondID = try XCTUnwrap(windows.open(second, deliver: { opened.append($0) }))
        XCTAssertEqual(opened, [firstID, secondID])
        XCTAssertNotEqual(firstID, secondID)
        let firstWindow = UUID()
        let secondWindow = UUID()
        windows.attach(firstID, owner: firstWindow)
        windows.attach(secondID, owner: secondWindow)
        XCTAssertEqual(windows.request(firstID, owner: firstWindow)?.document.encoded(), first.encoded())
        XCTAssertEqual(windows.request(secondID, owner: secondWindow)?.document.encoded(), second.encoded())
        windows.attach(firstID, owner: secondWindow)
        XCTAssertNil(windows.request(firstID, owner: secondWindow))
        windows.close(firstID, owner: secondWindow)
        XCTAssertNotNil(windows.request(firstID, owner: firstWindow))
        windows.close(firstID, owner: firstWindow)
        XCTAssertNil(windows.request(firstID, owner: firstWindow))
        windows.attach(firstID, owner: firstWindow)
        XCTAssertNil(windows.request(firstID, owner: firstWindow))
        XCTAssertNotNil(windows.request(secondID, owner: secondWindow))
        windows.close(secondID, owner: secondWindow)
    }

    func testUnknownRestoredAndOverCapacityRequestsNeverRetarget() throws {
        let windows = WorkflowReplayWindows(maximumCount: 1)
        let source = try document("source")
        let owner = UUID()
        let id = try XCTUnwrap(windows.open(source, deliver: { _ in }))
        windows.attach(nil, owner: owner)
        windows.attach(UUID(), owner: owner)
        XCTAssertNil(windows.request(nil, owner: owner))
        XCTAssertNil(windows.request(UUID(), owner: owner))
        XCTAssertNil(windows.request(id, owner: owner))
        XCTAssertFalse(windows.hasCapacity)
        XCTAssertNil(windows.open(source, deliver: { _ in XCTFail("Over capacity opened a window") }))
        windows.attach(id, owner: owner)
        windows.close(id, owner: owner)
        XCTAssertTrue(windows.hasCapacity)
    }

    func testUnattachedRequestExpiresAndReleasesCapacity() async throws {
        let windows = WorkflowReplayWindows(maximumCount: 1, pendingLifetime: .zero)
        let id = try XCTUnwrap(windows.open(try document("unused"), deliver: { _ in }))
        for _ in 0..<100 {
            if windows.hasCapacity { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(windows.hasCapacity)
        let owner = UUID()
        windows.attach(id, owner: owner)
        XCTAssertNil(windows.request(id, owner: owner))
    }

    func testReplayCommandRequiresPartsOrALoadedReferenceImage() async throws {
        let store = makeStore()
        defer { store.stop() }
        let blank = try document("blank")
        await store.load(data: blank.encoded())
        XCTAssertNil(store.workflowReplayCommand)

        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        let reference = try blank.applying(.setReferenceImagePNG(png))
        await store.load(data: reference.encoded())
        for _ in 0..<100 {
            if !store.isLoadingReferenceImage { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(store.referenceImage)
        let command = try XCTUnwrap(store.workflowReplayCommand)

        await store.load(data: blank.encoded())
        XCTAssertNil(store.workflowReplayCommand)
        command.invoke(in: store, windows: WorkflowReplayWindows()) { _ in
            XCTFail("A retired reference image opened replay")
        }
    }

    func testFocusedCommandRejectsAnotherWindowReplacementAndFailedLoad() async throws {
        let first = makeStore()
        let second = makeStore()
        defer {
            first.stop()
            second.stop()
        }
        let windows = WorkflowReplayWindows()
        var opened: [UUID] = []
        let original = try modelDocument("first")
        await first.load(data: original.encoded())
        await second.load(data: try modelDocument("second").encoded())
        let command = try XCTUnwrap(first.workflowReplayCommand)

        command.invoke(in: second, windows: windows) { opened.append($0) }
        XCTAssertTrue(opened.isEmpty)
        command.invoke(in: first, windows: windows) { opened.append($0) }
        let id = try XCTUnwrap(opened.first)
        let owner = UUID()
        windows.attach(id, owner: owner)

        let replacement = try modelDocument("replacement")
        await first.load(data: replacement.encoded())
        command.invoke(in: first, windows: windows) { opened.append($0) }
        XCTAssertEqual(opened, [id])
        XCTAssertEqual(windows.request(id, owner: owner)?.document.encoded(), original.encoded())

        let replacementCommand = try XCTUnwrap(first.workflowReplayCommand)
        await first.load(data: Data("invalid archive".utf8))
        XCTAssertNil(first.workflowReplayCommand)
        replacementCommand.invoke(in: first, windows: windows) { opened.append($0) }
        XCTAssertEqual(opened, [id])
        windows.close(id, owner: owner)
    }

    private func document(_ marker: String) throws -> Dust3DDocument {
        try Dust3DDocument(snapshotXML: Data("<canvas marker='\(marker)'/>".utf8))
    }

    private func modelDocument(_ marker: String) throws -> Dust3DDocument {
        try document(marker).applying(
            .addNode(
                id: "node", partID: "part", componentID: "component", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
    }

    private func makeStore() -> EditorStore {
        let stub = ReplayWindowsNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }
}

private struct ReplayWindowsNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
