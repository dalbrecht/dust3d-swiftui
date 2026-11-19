import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class RigSettingsOwnershipTests: XCTestCase {
    func testRetainedControlsCannotEditAReplacementWithIdenticalRigSettings() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try archive("first"), fileIdentity: UUID())
        let original = try XCTUnwrap(store.snapshot)
        let originalTarget = try XCTUnwrap(store.rigSettingsTarget)
        let choose = { store.editRigSettings(.template(.fish), target: originalTarget) }
        let toggle = { store.editRigSettings(.eyelids(true), target: originalTarget) }

        let replacement = try archive("second")
        await store.load(data: replacement, fileIdentity: UUID())
        let opened = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(opened.rigSettings, original.rigSettings)
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }

        choose()
        try await settle(store)
        toggle()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertFalse(store.canUndo)

        let target = try XCTUnwrap(store.rigSettingsTarget)
        store.select("a")
        try await settle(store)
        store.editRigSettings(.template(.bird), target: target)
        try await settle(store)
        let changed = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(changed.rigSettings.rigType, .bird)
        XCTAssertEqual(changed.selectedIDs, ["a"])
        XCTAssertEqual(changed.edges, opened.edges)
        XCTAssertEqual(try changed.document.animations(), try opened.document.animations())
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(changed.document.encoded(), try opened.document.applying(.setRigType(.bird)).encoded())
        store.editRigSettings(.eyelids(true), target: target)
        try await settle(store)
        XCTAssertEqual(writes.count, 1, "A control from the preceding revision cannot dispatch")
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement)
        XCTAssertFalse(store.canUndo)
    }

    func testFailedReloadRetiresStoreAndActorRigTargets() async throws {
        let original = try archive("original")
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: original)
        let target = try XCTUnwrap(store.rigSettingsTarget)
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }

        await store.load(data: Data("invalid archive".utf8), fileIdentity: UUID())
        let error = try XCTUnwrap(store.errorMessage)
        XCTAssertNil(store.rigSettingsTarget)
        store.editRigSettings(.template(.fish), target: target)
        store.editRigSettings(.eyelids(true), target: target)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertEqual(store.errorMessage, error)
        XCTAssertTrue(writes.isEmpty)

        let session = EditorSession()
        let opened = try await session.open(data: original)
        let actorTarget = RigSettingsTarget(snapshot: opened)
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid source must fail admission")
        } catch {}
        for edit in [RigSettingsEdit.template(.fish), .eyelids(true)] {
            do {
                _ = try await session.editRigSettings(edit, target: actorTarget)
                XCTFail("Failed replacement must retire accepted rig settings")
            } catch {
                XCTAssertEqual(error as? RigSettingsEditError, .staleSource)
            }
        }
        let retained = try await session.animationSnapshot().editor
        XCTAssertEqual(retained.document.encoded(), original)
        XCTAssertFalse(retained.canUndo)

        let recovered = try await session.open(data: original)
        let changed = try await session.editRigSettings(.eyelids(true), target: .init(snapshot: recovered))
        XCTAssertTrue(changed.rigSettings.headHasEyelids)
        XCTAssertEqual(changed.rigSettings.sourceRigType, "Biped")
        XCTAssertEqual(changed.document.encoded(), try recovered.document.applying(.setHeadHasEyelids(true)).encoded())
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original)
    }

    private func archive(_ marker: String) throws -> Data {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas rigType='Biped' headHasEyelids='False' future='\(marker)'>
                  <nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p' x='.1' y='0' z='0' radius='.1'/></nodes>
                  <edges><edge id='e' partId='p' from='a' to='b' boneName='Head' opaque='preserve'/></edges>
                  <parts><part id='p'/></parts>
                  <animations><animation id='motion' name='Walk' type='future' param='retained'/></animations>
                </canvas>
                """.utf8)
        ).encoded()
    }

    private func makeStore() -> EditorStore {
        let stub = RigSettingsNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Rig settings edit did not settle")
    }
}

private struct RigSettingsNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
