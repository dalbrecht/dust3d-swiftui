import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class GraphWheelQueueTests: XCTestCase {
    func testBusyWheelPreservesSignedRadiusAndSpacingSamplesAsSeparateUndoSteps() async throws {
        let store = makeStore()
        defer { store.stop() }
        let source = try await open(store)
        store.selectEdges(["e"])
        try await settle(store)
        var writes: [Data] = []
        store.onDocumentChanged = { writes.append($0) }

        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))
        XCTAssertTrue(store.isWorking)
        XCTAssertTrue(store.canRouteGraphWheelWhileWorking)
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1, modifiers: .command)))
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: -1)))
        try await settle(store)
        XCTAssertEqual(writes.count, 3)
        let nodes = try XCTUnwrap(store.snapshot?.nodes)
        XCTAssertEqual(nodes[0].value.radius, 0.1, accuracy: 1e-12)
        XCTAssertEqual(nodes[1].value.radius, 0.3, accuracy: 1e-12)
        XCTAssertEqual(nodes[0].value.position.x, -0.005, accuracy: 1e-12)
        store.undo()
        try await settle(store)
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes[0].value.radius), 0.11, accuracy: 1e-12)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes[0].value.position.x, 0)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
    }

    func testOverflowConsumesExcessWithoutAddingEditsOrLeakingToAnotherRoute() async throws {
        let store = makeStore()
        defer { store.stop() }
        _ = try await open(store)
        store.select("a")
        try await settle(store)
        var writes = 0
        store.onDocumentChanged = { _ in writes += 1 }

        for _ in 0..<40 {
            XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))
        }
        try await settle(store)
        XCTAssertEqual(writes, 33, "One in flight and at most 32 pending samples")
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes[0].value.radius), 0.43, accuracy: 1e-12)
    }

    func testPaneChangeAndHoverExitRetireQueuedSamples() async throws {
        for changesPane in [true, false] {
            let store = makeStore()
            defer { store.stop() }
            _ = try await open(store)
            if changesPane {
                store.select("a")
                try await settle(store)
            } else {
                store.setHoveredNode("a")
            }
            var writes = 0
            store.onDocumentChanged = { _ in writes += 1 }
            XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))
            XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))
            if changesPane { store.plane = .side } else { store.clearCanvasHover() }
            try await settle(store)
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes[0].value.radius), 0.11, accuracy: 1e-12)
        }
    }

    func testStationaryHoveredNodeKeepsBothSamplesWithoutSelectingGeometry() async throws {
        let store = makeStore()
        defer { store.stop() }
        _ = try await open(store)
        store.setHoveredNode("a")

        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))
        try await settle(store)
        let nodes = try XCTUnwrap(store.snapshot?.nodes)
        XCTAssertEqual(nodes[0].value.radius, 0.12, accuracy: 1e-12)
        XCTAssertEqual(nodes[1].value.radius, 0.3, accuracy: 1e-12)
        XCTAssertTrue(try XCTUnwrap(store.snapshot).selectedIDs.isEmpty)
        XCTAssertFalse(store.canRouteGraphWheelWhileWorking)
    }

    func testReplacementDiscardsAnOwnedQueueBeforeAcceptingNewWheelSamples() async throws {
        let store = makeStore()
        defer { store.stop() }
        let original = try await open(store)
        store.select("a")
        try await settle(store)
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: 1)))

        await store.load(data: original, fileIdentity: UUID())
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
        store.select("a")
        try await settle(store)
        store.setCanvasHeight(100)
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: -1)))
        try await settle(store)
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes[0].value.radius), 0.09, accuracy: 1e-12)
    }

    private func open(_ store: EditorStore) async throws -> Data {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                <node id='b' partId='p' x='1' y='1' z='1' radius='.3'/></nodes>
                <edges><edge id='e' partId='p' from='a' to='b'/></edges><parts><part id='p'/></parts></canvas>
                """.utf8)
        ).encoded()
        await store.load(data: source)
        try await settle(store)
        store.setCanvasHeight(100)
        return source
    }

    private func makeStore() -> EditorStore {
        let stub = GraphWheelNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Wheel edits did not settle")
    }
}

private struct GraphWheelNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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
