import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct RigEdgeSidebarNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class RigEdgeSidebarAdmissionTests: XCTestCase {
    private func setup() async throws -> (EditorStore, Data) {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
                <node id='c' partId='locked' x='0' y='1' z='0' radius='.1'/>
                <node id='d' partId='locked' x='1' y='1' z='0' radius='.1'/>
                <node id='e' partId='hidden' x='0' y='2' z='0' radius='.1'/>
                <node id='f' partId='hidden' x='1' y='2' z='0' radius='.1'/>
                </nodes><edges><edge id='ab' partId='p' from='a' to='b'/>
                <edge id='cd' partId='locked' from='c' to='d'/>
                <edge id='ef' partId='hidden' from='e' to='f'/></edges>
                <parts><part id='p'/><part id='locked' locked='true'/><part id='hidden' visible='false'/></parts>
                </canvas>
                """.utf8)
        ).encoded()
        let stub = RigEdgeSidebarNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
        await store.load(data: original)
        return (store, original)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Edge selection did not settle")
    }

    private func action(_ edge: String, in store: EditorStore) throws -> @MainActor (GraphSelectionMode) -> Void {
        store.edgeSidebarSelectionAction(edge, context: .init(snapshot: try XCTUnwrap(store.snapshot)))
    }

    func testRigSidebarMatchesCanvasEligibilityAndKeepsValidPicks() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        store.setRigEdgeSelection(true)
        let locked = try action("cd", in: store)
        let hidden = try action("ef", in: store)
        let eligible = try action("ab", in: store)
        eligible(.replace)
        try await settle(store)
        let before = try XCTUnwrap(store.snapshot)
        XCTAssertTrue(EdgeBoneAssignmentTarget(snapshot: before).isAvailable)
        for mode in [GraphSelectionMode.replace, .add, .toggle] {
            locked(mode)
            hidden(mode)
            XCTAssertFalse(store.isWorking)
        }
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 300)
        store.pickEdge(at: projection.point(for: .init(x: 0.5, y: 1, z: 0)), projection: projection, mode: .add)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testReadonlyInspectionAndRemovalSurviveButRetainedActionCannotCrossRigModeABA() async throws {
        let (store, original) = try await setup()
        defer { store.stop() }
        let ordinary = try action("cd", in: store)
        ordinary(.replace)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["cd"])

        store.setRigEdgeSelection(true)
        let rigRemoval = try action("cd", in: store)
        let oldEligible = try action("ab", in: store)
        ordinary(.subtract)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["cd"])
        rigRemoval(.subtract)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])

        store.setRigEdgeSelection(false)
        store.setRigEdgeSelection(true)
        oldEligible(.add)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        store.setRigEdgeSelection(false)
        ordinary(.replace)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        try action("ef", in: store)(.replace)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, ["ef"])
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }
}
