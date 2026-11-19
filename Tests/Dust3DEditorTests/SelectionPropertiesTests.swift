import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class SelectionPropertiesTests: XCTestCase {
    func testPropertiesShowsExistingSelectionInspectorForExplicitNodesAndEdges() async throws {
        let store = makeStore()
        defer { store.stop() }
        let bytes = try fixture("Capsule")
        await store.load(data: bytes)
        let initial = try XCTUnwrap(store.snapshot)
        let node = try XCTUnwrap(initial.nodes.first?.id)
        let edge = try XCTUnwrap(initial.edges.first?.id)
        var presentation = EditorInspectorPresentation(isPresented: false, section: .animations)
        for (nodes, edges): (Set<String>, Set<String>) in [([node], []), ([], [edge]), ([node], [edge])] {
            store.selectGraph(nodes: nodes, edges: edges)
            try await settle(store)
            let before = try XCTUnwrap(store.snapshot)
            let action = try XCTUnwrap(store.selectionPropertiesAction { presentation.showSelectionProperties() })
            XCTAssertTrue(space.routeSelectionProperties(action: action))
            XCTAssertTrue(presentation.isPresented)
            XCTAssertEqual(presentation.section, .selection)
            XCTAssertEqual(store.snapshot?.selectedIDs, nodes)
            XCTAssertEqual(store.snapshot?.selectedEdgeIDs, edges)
            XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
            XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision)
            XCTAssertEqual(store.snapshot?.documentRevision, before.documentRevision)
            XCTAssertFalse(store.canUndo)
            presentation = EditorInspectorPresentation(isPresented: false, section: .animations)
        }
    }

    func testRetainedActionRejectsSelectionABAProfileChangeAndFailedReplacement() async throws {
        let store = makeStore()
        defer { store.stop() }
        await store.load(data: try fixture("Capsule"))
        let initial = try XCTUnwrap(store.snapshot)
        let node = try XCTUnwrap(initial.nodes.first?.id)
        let alternate = try XCTUnwrap(initial.nodes.last?.id)
        var presentations = 0
        store.select(node)
        try await settle(store)
        let retained = try XCTUnwrap(store.selectionPropertiesAction { presentations += 1 })
        store.select(alternate)
        try await settle(store)
        store.select(node)
        try await settle(store)
        XCTAssertFalse(retained())

        let profile = try XCTUnwrap(store.selectionPropertiesAction { presentations += 1 })
        store.setDualCanvasProfile(true)
        store.plane = .side
        XCTAssertFalse(profile())

        let replacement = try XCTUnwrap(store.selectionPropertiesAction { presentations += 1 })
        await store.load(data: Data("invalid".utf8))
        XCTAssertFalse(replacement())
        XCTAssertNil(store.selectionPropertiesAction { presentations += 1 })
        XCTAssertEqual(presentations, 0)
    }

    func testHoverOnlyAndMixedOwnersLeaveInspectorUntouched() async throws {
        let store = makeStore()
        defer { store.stop() }
        let bytes = try fixture("Sword")
        await store.load(data: bytes)
        let snapshot = try XCTUnwrap(store.snapshot)
        let first = try XCTUnwrap(snapshot.nodes.first)
        let other = try XCTUnwrap(snapshot.nodes.first { $0.partID != first.partID })
        store.setHoveredNode(first.id)
        XCTAssertNil(store.selectionPropertiesAction { XCTFail("Hover-only opened properties") })
        store.select(first.id)
        try await settle(store)
        let action = try XCTUnwrap(store.selectionPropertiesAction { XCTFail("Foreign hover opened properties") })
        store.setHoveredNode(other.id)
        XCTAssertFalse(action())
        XCTAssertNil(store.selectionPropertiesAction { XCTFail("Foreign hover opened properties") })
        store.clearCanvasHover()
        store.select([first.id, other.id])
        try await settle(store)
        XCTAssertNil(store.selectionPropertiesAction { XCTFail("Mixed owners opened properties") })
        XCTAssertEqual(store.snapshot?.document.encoded(), bytes)
        XCTAssertFalse(store.canUndo)
    }

    func testSpaceKeyIsBareAndRepeatDoesNotPresentAgain() {
        var presentations = 0
        let action: @MainActor () -> Bool = {
            presentations += 1
            return true
        }
        XCTAssertTrue(space.requiresActiveCanvasWindow)
        XCTAssertFalse(space.routeSelectionProperties(action: nil))
        XCTAssertTrue(space.routeSelectionProperties(action: action))
        let repeatSpace = CanvasPrecisionKeyInput(keyCode: 49, characters: " ", modifiers: [], isRepeat: true)
        XCTAssertTrue(repeatSpace.routeSelectionProperties(action: action))
        for modifiers: NSEvent.ModifierFlags in [.command, .option, .shift, .control, .function] {
            let modified = CanvasPrecisionKeyInput(keyCode: 49, characters: " ", modifiers: modifiers)
            XCTAssertFalse(modified.routeSelectionProperties(action: action))
        }
        XCTAssertFalse(
            CanvasPrecisionKeyInput(keyCode: 0, characters: "a", modifiers: []).routeSelectionProperties(action: action)
        )
        XCTAssertEqual(presentations, 1)
    }

    private var space: CanvasPrecisionKeyInput { .init(keyCode: 49, characters: " ", modifiers: []) }

    private func fixture(_ name: String) throws -> Data {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures")
        return try Data(contentsOf: fixtures.appendingPathComponent(name + ".ds3"))
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Selection did not settle")
    }

    private func makeStore() -> EditorStore {
        let stub = SelectionPropertiesNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }
}

private struct SelectionPropertiesNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        throw CancellationError()
    }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}
