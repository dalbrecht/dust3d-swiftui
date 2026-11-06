import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct InspectorNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class GraphInspectorActionStoreTests: XCTestCase {
    private func source(locked: Bool = false) throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.3' y='.5' z='.5' radius='.1'/><node id='c' partId='p' x='.4' y='.5' z='.5' radius='.1'/><node id='x' partId='q' x='.8' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p' locked='\(locked)'/><part id='q'/></parts><components><component id='cp' linkDataType='partId' linkData='p'/><component id='cq' linkDataType='partId' linkData='q'/></components></canvas>
                """.utf8))
    }
    private func store() -> EditorStore {
        let stub = InspectorNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Inspector Store did not settle")
    }
    private func context(_ value: EditorStore) throws -> GraphInspectorActionContext {
        .init(snapshot: try XCTUnwrap(value.snapshot))
    }

    func testBoneSelectionFactoryPublishesNoDocumentAndKeepsOtherWindowSelection() async throws {
        let original = try source().applying(.setEdgeBoneName(id: "ab", name: "Arm"))
            .applying(.setEdgeBoneName(id: "bc", name: "Arm"))
        let value = store()
        let other = store()
        defer {
            value.stop()
            other.stop()
        }
        await value.load(data: original.encoded())
        await other.load(data: original.encoded())
        try await settle(value)
        try await settle(other)
        value.selectGraph(nodes: [], edges: ["ab"])
        other.selectGraph(nodes: [], edges: ["ab"])
        try await settle(value)
        try await settle(other)
        let target = try context(value).target(for: .selectBoneEdges(edgeID: "ab"))
        XCTAssertTrue(value.canPerformInspectorAction(target))
        let revision = value.snapshot?.documentRevision
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        let action = value.inspectorAction(target)
        action()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab", "bc"])
        XCTAssertEqual(other.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(value.snapshot?.documentRevision, revision)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(value.canUndo)
        value.selectGraph(nodes: [], edges: ["bc"])
        try await settle(value)
        action()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["bc"])
        XCTAssertEqual(publications, 0)
    }

    func testUnavailableBoneFactoryNeverUsesLaterAssignment() async throws {
        let original = try source()
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectGraph(nodes: [], edges: ["ab"])
        try await settle(value)
        let target = try context(value).target(for: .selectBoneEdges(edgeID: "ab"))
        XCTAssertFalse(value.canPerformInspectorAction(target))
        let action = value.inspectorAction(target)
        try await value.load(data: original.applying(.setEdgeBoneName(id: "ab", name: "Arm")).encoded())
        try await settle(value)
        value.selectGraph(nodes: [], edges: ["ab"])
        try await settle(value)
        let before = value.snapshot?.selectionRevision
        action()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectionRevision, before)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
    }

    func testEachDocumentFactoryPublishesOnceWithExactUndoRedoAndWindowIsolation() async throws {
        let cases: [(GraphInspectorAction, Set<String>, Set<String>)] = [
            (.connect(from: "a", to: "x"), ["a"], []), (.deleteNode(id: "b"), ["b"], []),
            (.reverseEdge(id: "ab"), ["a"], []), (.disconnectEdge(id: "ab"), [], ["ab"]),
            (.insertMidpoint(edgeID: "ab"), [], ["ab"]),
        ]
        for (kind, nodes, edges) in cases {
            let value = store()
            let other = store()
            defer {
                value.stop()
                other.stop()
            }
            let original = try source()
            await value.load(data: original.encoded())
            await other.load(data: original.encoded())
            try await settle(value)
            try await settle(other)
            value.selectGraph(nodes: nodes, edges: edges)
            other.selectGraph(nodes: nodes, edges: edges)
            try await settle(value)
            try await settle(other)
            let target = try context(value).target(for: kind)
            XCTAssertTrue(value.canPerformInspectorAction(target))
            XCTAssertFalse(other.canPerformInspectorAction(target))
            var publications = 0
            value.onDocumentChanged = { _ in publications += 1 }
            let action = value.inspectorAction(target)
            action()
            try await settle(value)
            let after = try XCTUnwrap(value.snapshot?.document.encoded())
            XCTAssertNotEqual(after, original.encoded())
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
            action()
            try await settle(value)
            XCTAssertEqual(publications, 1)
            value.undo()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(value.canUndo)
            value.redo()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), after)
        }
    }

    func testReadonlyEndpointSelectionFactoryDoesNotPublishDocumentOrHistory() async throws {
        let value = store()
        defer { value.stop() }
        let original = try source(locked: true)
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectGraph(nodes: [], edges: ["ab"])
        try await settle(value)
        let target = try context(value).target(for: .selectEndpoints(edgeID: "ab"))
        XCTAssertTrue(value.canPerformInspectorAction(target))
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        value.inspectorAction(target)()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(value.canUndo)
    }

    func testRetainedConnectDoesNotRetargetAfterABAReplacementUndoOrStop() async throws {
        for change in 0..<5 {
            let value = store()
            defer { value.stop() }
            let original = try source()
            await value.load(data: original.encoded())
            try await settle(value)
            value.select("a")
            try await settle(value)
            let target = try context(value).target(for: .connect(from: "a", to: "x"))
            let action = value.inspectorAction(target)
            switch change {
            case 0:
                value.select("c")
                try await settle(value)
                value.select("a")
                try await settle(value)
            case 1:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
                try await settle(value)
            case 2:
                await value.load(data: original.encoded())
                try await settle(value)
            case 3:
                let reverse = try context(value).target(for: .reverseEdge(id: "ab"))
                value.inspectorAction(reverse)()
                try await settle(value)
                value.undo()
                try await settle(value)
            default: value.stop()
            }
            let before = value.snapshot?.document.encoded()
            let redo = value.canRedo
            var publications = 0
            value.onDocumentChanged = { _ in publications += 1 }
            action()
            try await settle(value)
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(value.snapshot?.document.encoded(), before)
            XCTAssertEqual(value.canRedo, redo)
            XCTAssertFalse(value.canPerformInspectorAction(target))
        }
    }

    func testUnavailableInvalidAndNilFactoriesNeverAcquireLaterFocus() async throws {
        let value = store()
        defer { value.stop() }
        let original = try source()
        await value.load(data: original.encoded())
        try await settle(value)
        let empty = try context(value).target(for: .deleteNode(id: "a"))
        let unavailable = value.inspectorAction(empty)
        let noSource = value.inspectorAction(nil)
        value.select("a")
        try await settle(value)
        let invalid = try context(value).target(for: .connect(from: "a", to: "missing"))
        unavailable()
        noSource()
        value.inspectorAction(invalid)()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }
}
