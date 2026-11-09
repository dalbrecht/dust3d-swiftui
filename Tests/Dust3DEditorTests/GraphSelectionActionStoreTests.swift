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
    private final class RigPresentation {
        var inspectorVisible = true
        var selectionSection = true
        var disclosureExpanded = true
    }

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
    func testCanvasAxisKeysToggleOnlyWindowLocksWithoutEditingSelectionOrSource() async throws {
        let original = try source().encoded()
        let value = store()
        let other = store()
        defer {
            value.stop()
            other.stop()
        }
        await value.load(data: original)
        await other.load(data: original)
        value.selectGraph(nodes: ["a"], edges: ["bc"])
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        var writes = 0
        value.onDocumentChanged = { _ in writes += 1 }

        let sequence: [(String, Set<EditingConstraint>)] = [
            ("x", [.x]), ("Y", [.x, .y]), ("z", [.x, .y, .z]), ("x", [.y, .z]),
        ]
        for (key, expected) in sequence {
            let input = CanvasPrecisionKeyInput(keyCode: 0, characters: key, modifiers: key == "Y" ? [.capsLock] : [])
            XCTAssertTrue(value.canvasAxisLockKeyHandler(profileLease: nil)(input))
            try await settle(value)
            XCTAssertEqual(value.locks, expected)
        }
        let after = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(after.document.encoded(), original)
        XCTAssertEqual(after.documentRevision, before.documentRevision)
        XCTAssertEqual(after.previewIdentity, before.previewIdentity)
        XCTAssertEqual(after.selectedIDs, before.selectedIDs)
        XCTAssertEqual(after.selectedEdgeIDs, before.selectedEdgeIDs)
        XCTAssertTrue(other.locks.isEmpty)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(writes, 0)
    }

    func testCanvasAxisKeysRejectModifiedRepeatedRetiredPaneAndConstraintABA() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        value.setDualCanvasProfile(true)
        prepareCanvas(value)
        value.select("a")
        try await settle(value)
        let lease = value.canvasProfiles.lease
        let retained = value.canvasAxisLockKeyHandler(profileLease: lease)
        let bare = CanvasPrecisionKeyInput(keyCode: 0, characters: "x", modifiers: [])
        XCTAssertFalse(retained(.init(keyCode: 0, characters: "x", modifiers: [.command])))
        XCTAssertFalse(retained(.init(keyCode: 0, characters: "X", modifiers: [.shift])))
        XCTAssertTrue(retained(.init(keyCode: 0, characters: "x", modifiers: [], isRepeat: true)))
        XCTAssertTrue(value.locks.isEmpty)

        value.setLock(.y, isLocked: true)
        try await settle(value)
        value.setLock(.y, isLocked: false)
        try await settle(value)
        XCTAssertFalse(retained(bare))

        let front = value.canvasAxisLockKeyHandler(profileLease: lease)
        let side = try XCTUnwrap(value.switchSelectedCanvasProfile(expectedLease: lease))
        XCTAssertFalse(front(bare))
        prepareCanvas(value)
        let beforeAdd = value.canvasAxisLockKeyHandler(profileLease: side)
        value.beginAddMode()
        XCTAssertTrue(value.isAddingNodes)
        XCTAssertFalse(beforeAdd(bare))
        XCTAssertFalse(value.canvasAxisLockKeyHandler(profileLease: side)(bare))
        value.cancelAddMode()
        XCTAssertFalse(beforeAdd(bare))

        let failedSource = value.canvasAxisLockKeyHandler(profileLease: side)
        await value.load(data: Data("broken".utf8))
        XCTAssertFalse(failedSource(bare))
        XCTAssertTrue(value.locks.isEmpty)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testCanvasAxisKeysQueueDistinctAndRepeatedAxesBeforePublication() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        let before = try XCTUnwrap(value.snapshot)
        var writes = 0
        value.onDocumentChanged = { _ in writes += 1 }
        let keys = value.canvasAxisLockKeyHandler(profileLease: nil)
        var admittedDuringDrain = false
        value.onEditingChanged = { [weak value] isWorking in
            if !isWorking, value?.snapshot?.constraintRevision == before.constraintRevision + 1 {
                admittedDuringDrain = keys(.init(keyCode: 0, characters: "z", modifiers: []))
            }
        }

        XCTAssertTrue(keys(.init(keyCode: 0, characters: "x", modifiers: [])))
        XCTAssertTrue(value.isWorking)
        XCTAssertTrue(keys(.init(keyCode: 0, characters: "y", modifiers: [])))
        XCTAssertTrue(keys(.init(keyCode: 0, characters: "x", modifiers: [])))
        try await settle(value)

        let after = try XCTUnwrap(value.snapshot)
        XCTAssertTrue(admittedDuringDrain)
        XCTAssertEqual(after.locks, [.y, .z])
        XCTAssertEqual(after.constraintRevision, before.constraintRevision + 4)
        XCTAssertEqual(after.document.encoded(), original)
        XCTAssertEqual(after.previewIdentity, before.previewIdentity)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(writes, 0)
    }

    func testCanvasAxisKeysDiscardQueuedInputAfterPaneRetires() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        value.setDualCanvasProfile(true)
        let keys = value.canvasAxisLockKeyHandler(profileLease: value.canvasProfiles.lease)
        XCTAssertTrue(keys(.init(keyCode: 0, characters: "x", modifiers: [])))
        XCTAssertTrue(keys(.init(keyCode: 0, characters: "y", modifiers: [])))
        value.plane = .side
        try await settle(value)

        XCTAssertEqual(value.locks, [.x])
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
        XCTAssertFalse(keys(.init(keyCode: 0, characters: "z", modifiers: [])))
    }

    func testCanvasPartStateHoverFirstThenUnambiguousFallbackWithExactUndo() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        prepareCanvas(value)
        value.select("x")
        try await settle(value)
        let projection = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 400, height: 300)
        value.updateCanvasHover(at: projection.point(for: .init(x: 0.3, y: 0.5, z: 0.5)), projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("ab"))
        var writes = 0
        value.onDocumentChanged = { _ in writes += 1 }
        let lock = CanvasPrecisionKeyInput(keyCode: 37, characters: "l", modifiers: [])
        XCTAssertTrue(value.canvasPartStateKeyHandler(profileLease: nil)(lock))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isLocked, true)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "q" }?.isLocked, false)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["x"])
        XCTAssertEqual(writes, 1)

        value.clearCanvasHover()
        let disable = try XCTUnwrap(value.canvasPartStateAction(.disabled))
        disable()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "q" }?.isDisabled, true)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["x"])
        XCTAssertEqual(writes, 2)
        let enable = CanvasPrecisionKeyInput(keyCode: 38, characters: "j", modifiers: [])
        XCTAssertTrue(value.canvasPartStateKeyHandler(profileLease: nil)(enable))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "q" }?.isDisabled, false)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["x"])
        XCTAssertEqual(writes, 3)
        for _ in 0..<3 {
            value.undo()
            try await settle(value)
        }
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testCanvasFSelectsHoveredOwnerAndRetainsCanvasPicks() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        prepareCanvas(value)
        value.select("x")
        try await settle(value)
        let key = CanvasPrecisionKeyInput(keyCode: 3, characters: "f", modifiers: [])
        XCTAssertFalse(value.canvasPartStateKeyHandler(profileLease: nil)(key))

        value.setHoveredNode("a")
        let retained = value.canvasPartStateKeyHandler(profileLease: nil)
        value.setHoveredNode("b")
        XCTAssertFalse(retained(key))
        let current = value.canvasPartStateKeyHandler(profileLease: nil)
        XCTAssertFalse(current(.init(keyCode: 3, characters: "f", modifiers: [.command])))
        XCTAssertTrue(current(.init(keyCode: 3, characters: "f", modifiers: [], isRepeat: true)))
        XCTAssertTrue(value.snapshot?.selectedComponentIDs.isEmpty == true)
        XCTAssertTrue(current(key))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["cp"])
        XCTAssertEqual(value.snapshot?.componentRevealHint?.componentID, "cp")
        XCTAssertEqual(value.snapshot?.selectedIDs, ["x"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testCanvasOwnerMenuUsesSelectedGraphAndRejectsAmbiguousOrRetiredPicks() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        prepareCanvas(value)

        value.selectGraph(nodes: ["a"], edges: ["ab"])
        try await settle(value)
        let select = try XCTUnwrap(value.selectedGraphOwningComponentAction())
        value.setHoveredNode("x")
        select()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["cp"])
        XCTAssertEqual(value.snapshot?.componentRevealHint?.componentID, "cp")
        XCTAssertEqual(value.snapshot?.selectedIDs, ["a"])
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])

        value.selectGraph(nodes: ["x"], edges: ["ab"])
        try await settle(value)
        XCTAssertNil(value.selectedGraphOwningComponentAction())
        value.select("a")
        try await settle(value)
        let retired = try XCTUnwrap(value.selectedGraphOwningComponentAction())
        value.select("x")
        try await settle(value)
        value.select("a")
        try await settle(value)
        retired()
        try await settle(value)
        XCTAssertTrue(value.snapshot?.selectedComponentIDs.isEmpty == true)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testSpaceOpensPropertiesWithoutReplacingGraphSelection() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        prepareCanvas(value)
        value.select("x")
        try await settle(value)
        value.setHoveredNode("a")
        let space = CanvasPrecisionKeyInput(keyCode: 49, characters: " ", modifiers: [])
        let key = value.canvasPartStateKeyHandler(profileLease: nil)
        XCTAssertTrue(key(.init(keyCode: 49, characters: " ", modifiers: [], isRepeat: true)))
        XCTAssertNil(value.canvasComponentProperties)
        XCTAssertTrue(key(space))
        let properties = try XCTUnwrap(value.canvasComponentProperties)
        value.clearCanvasHover()
        let before = try XCTUnwrap(value.snapshot)
        let target = try XCTUnwrap(properties.target(in: before))
        XCTAssertEqual(
            ComponentMeshSelectionPresentation(snapshot: before, target: target).components.map(\.id), ["cp", "cq"])
        XCTAssertEqual(before.selectedIDs, ["x"])
        XCTAssertEqual(before.document.encoded(), original)
        XCTAssertFalse(before.canUndo)
        value.componentMeshAction(.combineMode(.uncombined), target: target)()
        try await settle(value)
        let edited = try XCTUnwrap(value.snapshot)
        let updated = try XCTUnwrap(properties.target(in: edited))
        XCTAssertEqual(
            ComponentMeshSelectionPresentation(snapshot: edited, target: updated).combineMode, .uniform(.uncombined))
        XCTAssertEqual(edited.selectedIDs, ["x"])
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["x"])
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
        value.select("a")
        try await settle(value)
        XCTAssertNil(properties.target(in: try XCTUnwrap(value.snapshot)))
    }

    func testStationaryPartStateHoverLocksAndUnlocksTheSameOwner() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        prepareCanvas(value)
        value.select("x")
        try await settle(value)

        let projection = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 400, height: 300)
        value.updateCanvasHover(at: projection.point(for: .init(x: 0.3, y: 0.5, z: 0.5)), projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("ab"))
        let lock = CanvasPrecisionKeyInput(keyCode: 37, characters: "l", modifiers: [])
        let retained = value.canvasPartStateKeyHandler(profileLease: nil)
        XCTAssertTrue(retained(lock))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isLocked, true)

        XCTAssertFalse(retained(lock))
        XCTAssertTrue(value.canvasPartStateKeyHandler(profileLease: nil)(lock))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isLocked, false)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "q" }?.isLocked, false)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["x"])

        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isLocked, true)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testPointerMoveAndExitDuringPartLockRetireFormerHover() async throws {
        for exits in [false, true] {
            let value = store()
            defer { value.stop() }
            await value.load(data: try source().encoded())
            prepareCanvas(value)
            value.selectGraph(nodes: ["a", "x"], edges: [])
            try await settle(value)

            let projection = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 400, height: 300)
            value.updateCanvasHover(at: projection.point(for: .init(x: 0.3, y: 0.5, z: 0.5)), projection: projection)
            let lock = CanvasPrecisionKeyInput(keyCode: 37, characters: "l", modifiers: [])
            XCTAssertTrue(value.canvasPartStateKeyHandler(profileLease: nil)(lock))
            XCTAssertTrue(value.tracksPartStateHoverWhileWorking)
            let point = projection.point(for: .init(x: 0.8, y: 0.5, z: 0.5))
            value.updateCanvasHover(at: exits ? nil : point, projection: projection)
            try await settle(value)
            XCTAssertFalse(value.tracksPartStateHoverWhileWorking)
            XCTAssertEqual(value.canvasPartStateKeyHandler(profileLease: nil)(lock), !exits)
            try await settle(value)
            XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isLocked, true)
            XCTAssertEqual(value.snapshot?.parts.first { $0.id == "q" }?.isLocked, !exits)
        }
    }

    func testDisablingPartRetiresItsHoverWhenTheGraphChanges() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        prepareCanvas(value)
        value.selectGraph(nodes: ["a", "x"], edges: [])
        try await settle(value)
        let projection = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 400, height: 300)
        value.updateCanvasHover(at: projection.point(for: .init(x: 0.3, y: 0.5, z: 0.5)), projection: projection)
        let disable = CanvasPrecisionKeyInput(keyCode: 38, characters: "j", modifiers: [])
        XCTAssertTrue(value.canvasPartStateKeyHandler(profileLease: nil)(disable))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isDisabled, true)
        XCTAssertNil(value.canvasGraphHover)
        XCTAssertFalse(value.canvasPartStateKeyHandler(profileLease: nil)(disable))
        XCTAssertEqual(value.snapshot?.selectedIDs, ["a", "x"])
    }

    func testCanvasPartStateRejectsRetainedHoverAndToolEpochAndIgnoresRepeat() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        prepareCanvas(value)
        value.selectGraph(nodes: ["a", "x"], edges: [])
        try await settle(value)
        XCTAssertNil(value.canvasPartStateAction(.locked))
        value.setHoveredNode("a")
        let stale = value.canvasPartStateKeyHandler(profileLease: nil)
        let lock = CanvasPrecisionKeyInput(keyCode: 37, characters: "l", modifiers: [])
        value.setHoveredNode("x")
        value.setHoveredNode("a")
        XCTAssertFalse(stale(lock))
        let current = value.canvasPartStateKeyHandler(profileLease: nil)
        XCTAssertFalse(current(.init(keyCode: 37, characters: "l", modifiers: [.command])))
        XCTAssertTrue(current(.init(keyCode: 37, characters: "L", modifiers: [.capsLock], isRepeat: true)))
        XCTAssertFalse(value.canUndo)
        value.setRigEdgeSelection(true)
        try await settle(value)
        XCTAssertFalse(current(lock))
        XCTAssertNil(value.canvasPartStateAction(.locked))
        value.setRigEdgeSelection(false)
        value.setHoveredNode("a")
        let retained = try XCTUnwrap(value.canvasPartStateAction(.locked))
        await value.load(data: Data("broken".utf8))
        retained()
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testFreshPartStateHandlerDoesNotAcquireHoverFromBeforeResizeOrNodeMove() async throws {
        let value = store()
        defer { value.stop() }
        await value.load(data: try source().encoded())
        try await settle(value)
        prepareCanvas(value)
        value.select("x")
        try await settle(value)
        let lock = CanvasPrecisionKeyInput(keyCode: 37, characters: "l", modifiers: [])
        let initial = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 400, height: 300)
        let originalPosition = NodePosition(x: 0.2, y: 0.5, z: 0.5)
        value.updateCanvasHover(at: initial.point(for: originalPosition), projection: initial)
        XCTAssertEqual(value.canvasGraphHover, .node("a"))

        let resized = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 520, height: 360)
        value.setCanvasContext(projection: resized, width: 520, height: 360)
        value.updateCanvasHover(at: initial.point(for: originalPosition), projection: initial)
        XCTAssertTrue(value.canvasPartStateKeyHandler(profileLease: nil)(lock))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isLocked, false)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "q" }?.isLocked, true)
        value.undo()
        try await settle(value)

        value.selectGraph(nodes: ["a", "x"], edges: [])
        try await settle(value)
        value.updateCanvasHover(at: resized.point(for: originalPosition), projection: resized)
        XCTAssertEqual(value.canvasGraphHover, .node("a"))
        let movedPosition = NodePosition(x: 0.2, y: 0.75, z: 0.5)
        value.move(id: "a", to: movedPosition)
        try await settle(value)
        XCTAssertFalse(value.canvasPartStateKeyHandler(profileLease: nil)(lock))
        XCTAssertFalse(value.isWorking)
        try await settle(value)

        let current = CanvasProjection(bounds: value.bounds, plane: value.plane, width: 520, height: 360)
        value.setCanvasContext(projection: current, width: 520, height: 360)
        value.updateCanvasHover(at: current.point(for: movedPosition), projection: current)
        XCTAssertEqual(value.canvasGraphHover, .node("a"))
        XCTAssertTrue(value.canvasPartStateKeyHandler(profileLease: nil)(lock))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "p" }?.isLocked, true)
        XCTAssertEqual(value.snapshot?.parts.first { $0.id == "q" }?.isLocked, false)
    }

    func testCanvasPartStateRetiresOldPaneAndStaysUnavailableDuringAdd() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        value.setDualCanvasProfile(true)
        prepareCanvas(value)
        value.select("a")
        try await settle(value)
        let frontLease = value.canvasProfiles.lease
        let old = value.canvasPartStateKeyHandler(profileLease: frontLease)
        let lock = CanvasPrecisionKeyInput(keyCode: 37, characters: "l", modifiers: [])
        let sideLease = try XCTUnwrap(value.switchSelectedCanvasProfile(expectedLease: frontLease))
        XCTAssertFalse(old(lock))
        prepareCanvas(value)
        let side = value.canvasPartStateKeyHandler(profileLease: sideLease)
        value.beginAddMode()
        XCTAssertTrue(value.isAddingNodes)
        XCTAssertFalse(side(lock))
        XCTAssertNil(value.canvasPartStateAction(.locked))
        value.cancelAddMode()
        XCTAssertFalse(side(lock))
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
    }

    func testEscapeCanvasActionRejectsRetiredAddAndOriginModesAndPreservesSource() async throws {
        let original = try source().applying(.setOrigin(.init(x: 0.5, y: 0.5, z: 0.5))).encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        prepareCanvas(value)
        var writes = 0
        value.onDocumentChanged = { _ in writes += 1 }

        XCTAssertNil(value.canvasInputCancellationAction())
        value.beginAddMode()
        XCTAssertTrue(value.isAddingNodes)
        let oldAdd = try XCTUnwrap(value.canvasInputCancellationAction())
        value.cancelAddMode()
        value.beginAddMode()
        oldAdd()
        XCTAssertTrue(value.isAddingNodes)
        try XCTUnwrap(value.canvasInputCancellationAction())()
        XCTAssertFalse(value.isAddingNodes)

        value.setMovingOrigin(true)
        XCTAssertTrue(value.isMovingOrigin)
        let oldOrigin = try XCTUnwrap(value.canvasInputCancellationAction())
        value.setMovingOrigin(false)
        value.setMovingOrigin(true)
        oldOrigin()
        XCTAssertTrue(value.isMovingOrigin)
        try XCTUnwrap(value.canvasInputCancellationAction())()
        XCTAssertFalse(value.isMovingOrigin)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(writes, 0)
    }

    func testOrthogonalQuarterTurnCapturesProfileAndSelectionAndPublishesOneEdit() async throws {
        let original = try source()
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectGraph(nodes: ["a"], edges: ["ab"])
        try await settle(value)
        let staleProfile = try XCTUnwrap(value.orthogonalQuarterTurnAction(.positive))
        value.plane = .side
        staleProfile()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())

        let staleSelection = try XCTUnwrap(value.orthogonalQuarterTurnAction(.positive))
        value.select("x")
        try await settle(value)
        staleSelection()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertNil(value.orthogonalQuarterTurnAction(.positive))

        value.selectGraph(nodes: ["a"], edges: ["ab"])
        try await settle(value)
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        try XCTUnwrap(value.orthogonalQuarterTurnAction(.positive))()
        try await settle(value)
        XCTAssertEqual(value.plane, .side)
        XCTAssertEqual(value.snapshot?.selectedIDs, ["a"])
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertNotEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(publications, 1)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }

    func testOrthogonalQuarterTurnRejectsRetainedActionAfterReferenceInteraction() async throws {
        let original = try source()
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectGraph(nodes: ["a"], edges: ["ab"])
        try await settle(value)
        value.plane = .side
        let old = try XCTUnwrap(value.orthogonalQuarterTurnAction(.positive))
        value.setReferenceColorInteractionActive(true)
        XCTAssertNil(value.orthogonalQuarterTurnAction(.positive))
        value.setReferenceColorInteractionActive(false)
        old()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
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

    func testRigAssignmentCommandRechecksLiveInspectorAndDisclosureBeforeUnmount() async throws {
        let xml = String(decoding: try source().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "<canvas>", with: "<canvas rigType='Biped'>")
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        value.selectEdge("ab")
        try await settle(value)
        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let context = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: try XCTUnwrap(value.snapshot))
        let browser = RigAssignmentBrowserSelection()
        browser.setVisible(true)
        browser.select("Spine")
        let presentation = RigPresentation()
        let isPresented: @MainActor () -> Bool = {
            presentation.inspectorVisible && presentation.selectionSection && presentation.disclosureExpanded
        }
        let retained = try XCTUnwrap(browser.command(store: value, context: context, isPresented: isPresented))

        for field in [
            \RigPresentation.inspectorVisible, \RigPresentation.selectionSection, \RigPresentation.disclosureExpanded,
        ] {
            presentation[keyPath: field] = false
            XCTAssertNil(browser.command(store: value, context: context, isPresented: isPresented))
            XCTAssertFalse(retained.invoke(in: value))
            XCTAssertFalse(value.isWorking)
            presentation[keyPath: field] = true
        }

        let current = try XCTUnwrap(browser.command(store: value, context: context, isPresented: isPresented))
        XCTAssertTrue(current.invoke(in: value))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.edges.first?.boneName, "Spine")
        XCTAssertTrue(value.canUndo)
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

    func testRigEdgeModeKeepsEdgesLocksAndExactAssignmentUndo() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        value.setLock(.x, isLocked: true)
        try await settle(value)
        value.selectGraph(nodes: ["a"], edges: ["ab"])
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        let oldEpoch = value.rigEdgeSelectionEpoch
        let retiredToggle = value.rigEdgeSelectionToggleAction()
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        value.setRigEdgeSelection(true)
        try await settle(value)
        let active = try XCTUnwrap(value.snapshot)
        XCTAssertTrue(value.isSelectingRigEdges)
        XCTAssertTrue(active.selectedIDs.isEmpty)
        XCTAssertEqual(active.selectedEdgeIDs, ["ab"])
        XCTAssertEqual(active.locks, before.locks)
        XCTAssertEqual(active.document.encoded(), original)
        XCTAssertFalse(value.canUndo)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(value.admitsCanvasSelectionInput(epoch: oldEpoch, lease: nil))
        retiredToggle(false)
        XCTAssertTrue(value.isSelectingRigEdges)

        value.select("b")
        value.selectGraph(nodes: ["b"], edges: [], mode: .add)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertTrue(value.snapshot?.selectedIDs.isEmpty == true)
        value.assignBoneNameAction("Spine", target: EdgeBoneAssignmentTarget(snapshot: active))()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.edges.first { $0.id == "ab" }?.boneName, "Spine")
        XCTAssertTrue(value.isSelectingRigEdges)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
    }

    func testRigEdgeMarqueeKeepsNodePicksAndInferredTransformsOut() async throws {
        let original = try source().encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        prepareCanvas(value)
        value.setRigEdgeSelection(true)
        let activeEpoch = value.rigEdgeSelectionEpoch
        XCTAssertTrue(value.admitsCanvasSelectionInput(epoch: activeEpoch, lease: nil))
        let projection = CanvasProjection(bounds: value.bounds, plane: .front, width: 400, height: 300)
        let from = projection.point(for: .init(x: 0.2, y: 0.5, z: 0.5))
        let middle = projection.point(for: .init(x: 0.3, y: 0.5, z: 0.5))
        let endpointAndStroke = CanvasSelectionRectangle(
            from: .init(x: from.x - 2, y: from.y - 2), to: .init(x: middle.x + 2, y: middle.y + 2))
        value.selectMarquee(endpointAndStroke, projection: projection, mode: .replace)
        try await settle(value)
        XCTAssertTrue(value.snapshot?.selectedIDs.isEmpty == true)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertFalse(value.canTransform)
        XCTAssertFalse(value.canAdjustSelectionRadius)
        XCTAssertFalse(value.canPerformCanvasPrecision(.right))
        value.moveSelection(by: .init(x: 1, y: 0, z: 0))
        let second = projection.point(for: .init(x: 0.5, y: 0.5, z: 0.5))
        let crossing = CanvasSelectionRectangle(
            from: .init(x: second.x - 2, y: second.y - 2), to: .init(x: second.x + 2, y: second.y + 2))
        value.selectMarquee(crossing, projection: projection, mode: .add)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab", "bc"])
        value.selectMarquee(endpointAndStroke, projection: projection, mode: .toggle)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["bc"])
        value.selectMarquee(crossing, projection: projection, mode: .subtract)
        try await settle(value)
        XCTAssertTrue(value.snapshot?.selectedEdgeIDs.isEmpty == true)
        XCTAssertEqual(value.snapshot?.document.encoded(), original)
        value.setRigEdgeSelection(false)
        XCTAssertFalse(value.admitsCanvasSelectionInput(epoch: activeEpoch, lease: nil))
        value.setRigEdgeSelection(true)
        XCTAssertFalse(value.admitsCanvasSelectionInput(epoch: activeEpoch, lease: nil))
        await value.load(data: original)
        XCTAssertFalse(value.isSelectingRigEdges)
    }

    func testRigEdgeHoverMatchesClickEligibilityAndRestoresOrdinaryHover() async throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='a' partId='p' x='.2' y='.3' z='.5' radius='.1'/>
                <node id='b' partId='p' x='.8' y='.3' z='.5' radius='.1'/>
                <node id='c' partId='q' x='.2' y='.7' z='.5' radius='.1'/>
                <node id='d' partId='q' x='.8' y='.7' z='.5' radius='.1'/>
                </nodes><edges>
                <edge id='ab' partId='p' from='a' to='b'/>
                <edge id='cd' partId='q' from='c' to='d'/>
                </edges><parts><part id='p'/><part id='q' locked='true'/></parts></canvas>
                """.utf8))
        let value = store()
        defer { value.stop() }
        await value.load(data: document.encoded())
        try await settle(value)
        let projection = CanvasProjection(bounds: value.bounds, plane: .front, width: 400, height: 300)
        let endpoint = projection.point(for: .init(x: 0.2, y: 0.3, z: 0.5))
        let lockedMiddle = projection.point(for: .init(x: 0.5, y: 0.7, z: 0.5))

        value.updateCanvasHover(at: endpoint, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .node("a"))
        value.updateCanvasHover(at: lockedMiddle, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("cd"))

        value.setRigEdgeSelection(true)
        value.updateCanvasHover(at: endpoint, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("ab"))
        value.pickEdge(at: endpoint, projection: projection, mode: .replace)
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        value.updateCanvasHover(at: lockedMiddle, projection: projection)
        XCTAssertNil(value.canvasGraphHover)
        value.pickEdge(at: lockedMiddle, projection: projection, mode: .add)
        XCTAssertFalse(value.isWorking)
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])

        value.setRigEdgeSelection(false)
        value.updateCanvasHover(at: endpoint, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .node("a"))
        value.updateCanvasHover(at: lockedMiddle, projection: projection)
        XCTAssertEqual(value.canvasGraphHover, .edge("cd"))
    }

    func testKeyboardAssignmentUsesEdgeOnlyCanvasSelectionAndExactUndo() async throws {
        let xml = String(decoding: try source().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "<canvas>", with: "<canvas rigType='Biped'>")
        let original = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let value = store()
        defer { value.stop() }
        await value.load(data: original)
        try await settle(value)
        value.setRigEdgeSelection(true)
        let projection = CanvasProjection(bounds: value.bounds, plane: .front, width: 400, height: 300)
        let endpoint = projection.point(for: .init(x: 0.2, y: 0.5, z: 0.5))
        value.pickEdge(at: endpoint, projection: projection, mode: .replace)
        try await settle(value)
        let picked = try XCTUnwrap(value.snapshot)
        XCTAssertEqual(picked.selectedEdgeIDs, ["ab"])
        XCTAssertTrue(picked.selectedIDs.isEmpty)

        let hierarchy = try XCTUnwrap(RigTemplateHierarchy.load(sourceType: "Biped"))
        let browser = RigAssignmentBrowserSelection()
        browser.setVisible(true)
        browser.select("Spine")
        let context = RigTemplateBrowserContext(hierarchy: hierarchy, snapshot: picked)
        let command = try XCTUnwrap(browser.command(store: value, context: context))
        var publications = 0
        value.onDocumentChanged = { _ in publications += 1 }
        XCTAssertTrue(command.invoke(in: value))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.edges.first { $0.id == "ab" }?.boneName, "Spine")
        XCTAssertEqual(value.snapshot?.selectedEdgeIDs, ["ab"])
        XCTAssertTrue(value.isSelectingRigEdges)
        XCTAssertEqual(publications, 1)
        XCTAssertTrue(value.canUndo)
        value.undo()
        try await settle(value)
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
