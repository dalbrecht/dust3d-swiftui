import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct ContextNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

private actor ContextPreviewCounter: EditorPreviewServing {
    var calls = 0
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        calls += 1
        throw CancellationError()
    }
    func reset(scopeID: UUID) async throws {}
}

@MainActor final class GraphSelectionActionStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='a' partId='p' x='.2' y='.5' z='.5' radius='.1'/><node id='b' partId='p' x='.4' y='.5' z='.5' radius='.1'/><node id='c' partId='p' x='.6' y='.5' z='.5' radius='.1'/><node id='x' partId='q' x='.8' y='.5' z='.5' radius='.1'/></nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p'/><part id='q'/></parts><components><component id='cp' linkDataType='partId' linkData='p'/><component id='cq' linkDataType='partId' linkData='q'/></components></canvas>
                """.utf8))
    }
    private func store() -> EditorStore {
        let stub = ContextNoNative()
        return EditorStore(
            preview: ContextPreviewCounter(), materialBaker: stub,
            importedMaterialLoader: stub, sourceMaterialBaker: stub, animationCatalog: stub)
    }
    private func prepareCanvas(_ value: EditorStore) {
        value.setCanvasContext(
            projection: CanvasProjection(bounds: value.bounds, plane: value.plane, width: 400, height: 300),
            width: 400, height: 300)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Context actions did not settle")
    }
    func testContextDeletePublishesOnceWithExactUndoAndIndependentWindow() async throws {
        let original = try source()
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
        value.select("a")
        other.select("x")
        try await settle(value)
        try await settle(other)
        let target = GraphSelectionActionTarget(snapshot: try XCTUnwrap(value.snapshot), action: .deleteSelection)
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        let action = value.graphSelectionAction(target)
        action()
        try await settle(value)
        let after = try XCTUnwrap(value.snapshot).document.encoded()
        XCTAssertFalse(try XCTUnwrap(value.snapshot).nodes.contains { $0.id == "a" })
        XCTAssertEqual(publications, 1)
        action()
        try await settle(value)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(other.snapshot?.selectedID, "x")
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        value.redo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), after)
    }
    func testCapturedMenuRejectsSelectionAndAddModeABA() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        value.select("a")
        try await settle(value)
        let target = GraphSelectionActionTarget(snapshot: try XCTUnwrap(value.snapshot), action: .deleteSelection)
        let oldSelection = value.graphSelectionAction(target)
        value.select("b")
        try await settle(value)
        value.select("a")
        try await settle(value)
        oldSelection()
        try await settle(value)
        XCTAssertFalse(value.canUndo)
        let current = GraphSelectionActionTarget(snapshot: try XCTUnwrap(value.snapshot), action: .deleteSelection)
        let oldMode = value.graphSelectionAction(current)
        prepareCanvas(value)
        value.beginAddMode()
        XCTAssertTrue(value.isAddingNodes)
        value.cancelAddMode()
        oldMode()
        try await settle(value)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(value.snapshot?.document.encoded(), try source().encoded())
    }
    func testContextCancellationDiscardsGhostWithoutAnEditAndRejectsOldModeLease() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        prepareCanvas(value)
        value.beginAddMode()
        let original = try XCTUnwrap(value.snapshot).document.encoded()
        let oldCancel = value.canvasAddCancellationAction()
        oldCancel()
        XCTAssertFalse(value.isAddingNodes)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        prepareCanvas(value)
        value.beginAddMode()
        oldCancel()
        XCTAssertTrue(value.isAddingNodes)
        value.canvasAddCancellationAction()()
        XCTAssertFalse(value.isAddingNodes)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }
    func testRigAssignmentCommandUsesOnlyTheCurrentBrowserAndWindow() async throws {
        let xml = String(decoding: try source().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "<canvas>", with: "<canvas rigType='Biped'>")
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let value = store()
        let other = store()
        defer {
            value.stop()
            other.stop()
        }
        await value.load(data: original)
        await other.load(data: original)
        value.selectEdges(["ab", "bc"])
        try await settle(value)
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let browser = RigAssignmentBrowserSelection()
        let context = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: try XCTUnwrap(value.snapshot))
        XCTAssertNil(browser.command(store: value, context: context))
        browser.setVisible(true)
        browser.select("Spine")
        let old = try XCTUnwrap(browser.command(store: value, context: context))
        XCTAssertFalse(old.invoke(in: other))
        XCTAssertFalse(old.invoke(in: value, focus: .init(hasKeyWindow: false)))
        XCTAssertFalse(old.invoke(in: value, focus: .init(hasSheet: true)))
        XCTAssertFalse(old.invoke(in: value, focus: .init(textEditing: true)))
        XCTAssertFalse(old.invoke(in: value, focus: .init(animationFocused: true)))
        browser.select("Head")
        browser.select("Spine")
        XCTAssertFalse(old.invoke(in: value))
        let beforeHide = try XCTUnwrap(browser.command(store: value, context: context))
        browser.setVisible(false)
        XCTAssertNil(browser.command(store: value, context: context))
        browser.setVisible(true)
        XCTAssertFalse(beforeHide.invoke(in: value))

        let current = try XCTUnwrap(browser.command(store: value, context: context))
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        XCTAssertTrue(current.invoke(in: value))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.edges.map(\.boneName), ["Spine", "Spine"])
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab", "bc"])
        XCTAssertEqual(publications, 1)
        XCTAssertFalse(current.invoke(in: value))
        XCTAssertEqual(other.snapshot?.document.encoded(), original)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testRigAssignmentCommandRetiresOnSelectionAndFailedSource() async throws {
        let xml = String(decoding: try source().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "<canvas>", with: "<canvas rigType='Biped'>")
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        value.selectEdges(["ab", "bc"])
        try await settle(value)
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let browser = RigAssignmentBrowserSelection()
        browser.setVisible(true)
        browser.select("Spine")
        let first = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: try XCTUnwrap(value.snapshot))
        let beforeSelection = try XCTUnwrap(browser.command(store: value, context: first))
        value.selectEdge("ab")
        try await settle(value)
        XCTAssertFalse(beforeSelection.invoke(in: value))
        let second = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: try XCTUnwrap(value.snapshot))
        let beforeFailure = try XCTUnwrap(browser.command(store: value, context: second))
        await value.load(data: Data("invalid".utf8))
        XCTAssertFalse(beforeFailure.invoke(in: value))
        XCTAssertNil(browser.command(store: value, context: second))
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testContextEntriesContainOnlyAvailableActionsAndPlaceDeleteLast() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        value.selectEdge("ab")
        try await settle(value)
        let actions = GraphSelectionMenuActions(store: value)
        XCTAssertEqual(actions.entries.map(\.action), [.insertMidpoints, .reverseEdges, .deleteSelection])
        XCTAssertEqual(actions.entries.last?.action, .deleteSelection)
        prepareCanvas(value)
        value.beginAddMode()
        XCTAssertTrue(GraphSelectionMenuActions(store: value).entries.isEmpty)
        value.cancelAddMode()
        let none = GraphSelectionMenuActions(store: nil)
        XCTAssertTrue(none.entries.isEmpty)
    }
}
