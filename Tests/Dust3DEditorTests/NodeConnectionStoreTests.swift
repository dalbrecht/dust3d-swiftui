import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct ConnectionNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class NodeConnectionStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='q' x='.8' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' name='Left'/><part id='q' name='Right'/></parts><components><component id='cp' linkDataType='partId' linkData='p'/><component id='cq' linkDataType='partId' linkData='q'/></components></canvas>
                """.utf8))
    }
    private func store() -> EditorStore {
        let stub = ConnectionNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Connection Store did not settle")
    }

    func testIdenticalNamesStillExposeDistinctOwnershipChoices() throws {
        var xml = String(decoding: try source().modelXML, as: UTF8.self)
        for quote in ["'", "\""] {
            xml = xml.replacingOccurrences(
                of: "id=\(quote)a\(quote)", with: "id=\(quote)a\(quote) name=\(quote)Same Node\(quote)"
            )
            .replacingOccurrences(
                of: "id=\(quote)b\(quote)", with: "id=\(quote)b\(quote) name=\(quote)Same Node\(quote)"
            )
            .replacingOccurrences(of: "name=\(quote)Left\(quote)", with: "name=\(quote)Same Part\(quote)")
            .replacingOccurrences(of: "name=\(quote)Right\(quote)", with: "name=\(quote)Same Part\(quote)")
        }
        var state = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        try state.select(["a", "b"])
        let target = NodeConnectionTarget(snapshot: state.snapshot)
        let titles = target.owners.map { NodeConnectionPresentation.title(owner: $0, choices: target.owners) }
        XCTAssertEqual(titles.count, 2)
        XCTAssertNotEqual(titles[0], titles[1])
        XCTAssertTrue(titles[0].contains("[a]"))
        XCTAssertTrue(titles[1].contains("[b]"))
    }

    func testCapturedOwnerPublishesOncePreservesOtherWindowAndHasExactUndoRedo() async throws {
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
        value.select(["a", "b"])
        try await settle(value)
        let target = NodeConnectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertTrue(value.canConnectSelectedNodes(target))
        XCTAssertFalse(other.canConnectSelectedNodes(target))
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        let action = value.nodeConnectionAction(target, ownerID: "b")
        action()
        try await settle(value)
        let joined = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(Set(joined.nodes.compactMap(\.partID)), ["q"])
        XCTAssertEqual(joined.edges.count, 1)
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
        XCTAssertEqual(value.snapshot?.document.encoded(), joined.document.encoded())
    }

    func testRetainedActionRejectsSelectionAndConstraintABAReplacementAndStop() async throws {
        for change in 0..<4 {
            let value = store()
            defer { value.stop() }
            let original = try source()
            await value.load(data: original.encoded())
            try await settle(value)
            value.select(["a", "b"])
            try await settle(value)
            let target = NodeConnectionTarget(snapshot: try XCTUnwrap(value.snapshot))
            let action = value.nodeConnectionAction(target, ownerID: "a")
            switch change {
            case 0:
                value.select("a")
                try await settle(value)
                value.select(["a", "b"])
                try await settle(value)
            case 1:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
                try await settle(value)
            case 2:
                await value.load(data: original.encoded())
                try await settle(value)
            default: value.stop()
            }
            let before = value.snapshot?.document.encoded()
            var publications = 0
            value.onDocumentChanged = { _ in publications += 1 }
            action()
            try await settle(value)
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(value.snapshot?.document.encoded(), before)
            XCTAssertFalse(value.canConnectSelectedNodes(target))
        }
    }

    func testMixedConnectionKeepsUnrelatedEdgeAndRejectsRetainedSelectionAndToolActions() async throws {
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas originX='0' originY='0' originZ='0'><nodes>
                <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='q' x='1' y='0' z='0' radius='.1'/>
                <node id='c' partId='r' x='2' y='0' z='0' radius='.1'/>
                <node id='d' partId='r' x='3' y='0' z='0' radius='.1'/>
                </nodes><edges><edge id='cd' from='c' to='d' partId='r'/></edges>
                <parts><part id='p'/><part id='q'/><part id='r'/></parts></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectGraph(nodes: ["a", "b"], edges: ["cd"])
        try await settle(value)
        let first = NodeConnectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertTrue(value.canConnectSelectedNodes(first))
        let oldSelection = value.nodeConnectionAction(first, ownerID: "b")
        value.selectGraph(nodes: ["a", "b"], edges: [])
        try await settle(value)
        value.selectGraph(nodes: ["a", "b"], edges: ["cd"])
        try await settle(value)
        oldSelection()
        XCTAssertFalse(value.isWorking)

        let current = NodeConnectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        let oldTool = value.nodeConnectionAction(current, ownerID: "b")
        value.setMovingOrigin(true)
        XCTAssertFalse(value.canConnectSelectedNodes(current))
        oldTool()
        XCTAssertFalse(value.isWorking)
        value.setMovingOrigin(false)
        oldTool()
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())

        var writes = 0
        value.onDocumentChanged = { _ in writes += 1 }
        value.nodeConnectionAction(current, ownerID: "b")()
        try await settle(value)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["a", "b"])
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["cd"])
        XCTAssertEqual(value.snapshot?.edges.count, 2)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }

    func testUnavailableOrWrongOwnerActionNeverAcquiresLaterSelection() async throws {
        let value = store()
        defer { value.stop() }
        let original = try source()
        await value.load(data: original.encoded())
        try await settle(value)
        let empty = NodeConnectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        let unavailable = value.nodeConnectionAction(empty, ownerID: "a")
        value.select(["a", "b"])
        try await settle(value)
        let target = NodeConnectionTarget(snapshot: try XCTUnwrap(value.snapshot))
        let invalid = value.nodeConnectionAction(target, ownerID: "missing")
        unavailable()
        invalid()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
        XCTAssertTrue(value.canConnectSelectedNodes(target))
    }
}
