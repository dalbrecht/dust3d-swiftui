import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

private struct AddProfileTransferNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
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

@MainActor final class AddProfileTransferStoreTests: XCTestCase {
    func testDualProfileSwitchRejectsOldCallbacksAndWaitsForFreshPointer() async throws {
        let source = Dust3DDocument.emptyArchive()
        let stub = AddProfileTransferNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: source)
        let before = try XCTUnwrap(store.snapshot)
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }

        store.setDualCanvasProfile(true)
        let frontLease = store.canvasProfiles.lease
        let front = CanvasProjection(bounds: store.bounds, plane: .front, width: 420, height: 240)
        store.setCanvasContext(projection: front, width: 420, height: 240, lease: frontLease)
        store.beginAddMode()
        let frontMode = store.addModeID
        let frontPoint = CanvasPoint(x: 210, y: 120)
        store.updateAddPointer(at: frontPoint, modeID: frontMode)
        XCTAssertTrue(store.canPlaceAddGhost)

        store.plane = .side
        let sideLease = store.canvasProfiles.lease
        let sideMode = store.addModeID
        XCTAssertNotEqual(sideLease, frontLease)
        XCTAssertNotEqual(sideMode, frontMode)
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(store.frozenAddProjection)
        XCTAssertNil(store.addGhostPoint)
        XCTAssertFalse(store.canPlaceAddGhost)

        store.setCanvasContext(projection: front, width: 420, height: 240, lease: frontLease)
        store.releaseCanvasProfile(lease: frontLease)
        store.updateAddPointer(at: frontPoint, modeID: frontMode)
        store.placeAddNode(at: frontPoint, modeID: frontMode)
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(store.frozenAddProjection)
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.canPlaceAddGhost)

        let side = CanvasProjection(bounds: store.bounds, plane: .side, width: 350, height: 180)
        store.setCanvasContext(projection: side, width: 350, height: 180, lease: sideLease)
        XCTAssertEqual(store.frozenAddProjection?.plane, .side)
        XCTAssertEqual(store.canvasHeight, 180)
        XCTAssertFalse(store.canPlaceAddGhost)
        store.updateAddPointer(at: frontPoint, modeID: frontMode)
        XCTAssertNil(store.addGhostPoint)
        let sidePoint = CanvasPoint(x: 190, y: 105)
        store.updateAddPointer(at: sidePoint, modeID: sideMode)
        XCTAssertEqual(store.addGhostPoint, sidePoint)
        XCTAssertTrue(store.canPlaceAddGhost)
        store.placeAddNode(at: frontPoint, modeID: frontMode)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.addGhostPoint, sidePoint)

        let after = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(after.document.encoded(), before.document.encoded())
        XCTAssertEqual(after.documentRevision, before.documentRevision)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(publications, 0)

        let expected = try side.position(at: sidePoint, hiddenCoordinate: before.origin?.x ?? 0.5)
        store.placeAddNode(at: sidePoint, modeID: sideMode)
        try await settle(store)
        let position = try XCTUnwrap(store.snapshot?.nodes.first?.value.position)
        XCTAssertEqual(position.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(position.y, expected.y, accuracy: 1e-12)
        XCTAssertEqual(position.z, expected.z, accuracy: 1e-12)
        XCTAssertEqual(publications, 1)
        XCTAssertTrue(store.canUndo)

        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), before.document.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func overlappingAddSource(
        farFirst: Bool, tie: Bool = false, nearInterior: Bool = false
    ) throws -> Dust3DDocument {
        let near = "<node id='near' partId='q' x='.5' y='.5' z='.4' radius='.1'/>"
        let far = "<node id='far' partId='r' x='\(tie ? ".5" : ".515")' y='.5' z='.6' radius='.1'/>"
        let ends =
            nearInterior
            ? "<node id='left' partId='q' x='.3' y='.5' z='.4' radius='.1'/><node id='right' partId='q' x='.7' y='.5' z='.4' radius='.1'/>"
            : ""
        let chain =
            nearInterior
            ? "<edge id='leftEdge' from='left' to='near' partId='q'/><edge id='rightEdge' from='near' to='right' partId='q'/>"
            : ""
        return try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='anchor' partId='p' x='.1' y='.5' z='.4' radius='.1'/>
                \(farFirst ? far + near : near + far)
                \(ends)
                </nodes><edges>\(chain)</edges>
                <parts><part id='p'/><part id='q'/><part id='r'/></parts></canvas>
                """.utf8))
    }

    private func clickOverlappingAddTargets(_ source: Dust3DDocument, in store: EditorStore) async throws {
        await store.load(data: source.encoded())
        store.select("anchor")
        try await settle(store)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: .front, width: 400, height: 300),
            width: 400, height: 300)
        store.beginAddMode()
        let projection = try XCTUnwrap(store.frozenAddProjection)
        let near = projection.point(for: try source.node(id: "near").position)
        let far = projection.point(for: try source.node(id: "far").position)
        XCTAssertLessThan(hypot(near.x - far.x, near.y - far.y), 18)
        store.updateAddPointer(at: near, modeID: store.addModeID)
        store.placeAddNode(at: near, modeID: store.addModeID)
        try await settle(store)
    }

    func testAddNearestNodeConnectsIndependentOfArchiveOrderAndUndoIsExact() async throws {
        for farFirst in [false, true] {
            let original = try overlappingAddSource(farFirst: farFirst)
            let stub = AddProfileTransferNoNative()
            let store = EditorStore(
                preview: stub, materialBaker: stub, importedMaterialLoader: stub,
                sourceMaterialBaker: stub, animationCatalog: stub)
            defer { store.stop() }
            try await clickOverlappingAddTargets(original, in: store)
            let snapshot = try XCTUnwrap(store.snapshot)
            let edge = try XCTUnwrap(snapshot.edges.first)
            XCTAssertEqual(Set([edge.fromID, edge.toID]), ["anchor", "near"])
            XCTAssertEqual(try snapshot.document.editorContents().nodes.first { $0.id == "far" }?.partID, "r")
            XCTAssertEqual(snapshot.nodes.count, 3)
            XCTAssertFalse(store.isAddingNodes)
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(store.canUndo)
        }
    }

    func testAddNearestNodePreservesTopmostExactTieAndNearestIneligibleFallback() async throws {
        for nearInterior in [false, true] {
            let original = try overlappingAddSource(farFirst: false, tie: !nearInterior, nearInterior: nearInterior)
            let stub = AddProfileTransferNoNative()
            let store = EditorStore(
                preview: stub, materialBaker: stub, importedMaterialLoader: stub,
                sourceMaterialBaker: stub, animationCatalog: stub)
            defer { store.stop() }
            try await clickOverlappingAddTargets(original, in: store)
            let snapshot = try XCTUnwrap(store.snapshot)
            let edge = try XCTUnwrap(snapshot.edges.first { $0.fromID == "anchor" || $0.toID == "anchor" })
            let other = edge.fromID == "anchor" ? edge.toID : edge.fromID
            if nearInterior {
                XCTAssertFalse(["near", "far"].contains(other))
                XCTAssertEqual(snapshot.nodes.count, 6)
                XCTAssertTrue(store.isAddingNodes)
            } else {
                XCTAssertEqual(other, "far")
                XCTAssertEqual(snapshot.nodes.count, 3)
                XCTAssertFalse(store.isAddingNodes)
            }
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(store.canUndo)
        }
    }

    func testAddEdgeArbitrationSuppressesOnlyCloserVisibleTaperedHitsAndUndoIsExact() async throws {
        enum Click: CaseIterable {
            case edgeMidpoint, exactNode, nearMiss, hiddenEdge, equalCenters
        }
        for click in Click.allCases {
            let edgeY = click == .equalCenters ? ".5" : ".51"
            let hidden = click == .hiddenEdge ? "visible='false'" : ""
            let source = try Dust3DDocument(
                snapshotXML: Data(
                    """
                    <canvas><nodes>
                    <node id='anchor' partId='p' x='.1' y='.5' z='.4' radius='.1'/>
                    <node id='target' partId='q' x='.5' y='.5' z='.4' radius='.1'/>
                    <node id='from' partId='r' x='.32' y='\(edgeY)' z='.4' radius='.1'/>
                    <node id='to' partId='r' x='.68' y='\(edgeY)' z='.4' radius='.1'/>
                    </nodes><edges><edge id='crossing' from='from' to='to' partId='r'/></edges>
                    <parts><part id='p'/><part id='q'/><part id='r' \(hidden)/></parts></canvas>
                    """.utf8))
            let stub = AddProfileTransferNoNative()
            let store = EditorStore(
                preview: stub, materialBaker: stub, importedMaterialLoader: stub,
                sourceMaterialBaker: stub, animationCatalog: stub)
            defer { store.stop() }
            await store.load(data: source.encoded())
            store.select("anchor")
            try await settle(store)
            store.setCanvasContext(
                projection: .init(bounds: store.bounds, plane: .front, width: 400, height: 300),
                width: 400, height: 300)
            store.beginAddMode()
            let projection = try XCTUnwrap(store.frozenAddProjection)
            let target = projection.point(for: try source.node(id: "target").position)
            let edge = projection.point(for: .init(x: 0.5, y: try XCTUnwrap(Double(edgeY)), z: 0.4))
            let point: CanvasPoint
            switch click {
            case .exactNode, .equalCenters: point = target
            case .nearMiss: point = .init(x: edge.x, y: edge.y + (edge.y > target.y ? 6 : -6))
            case .edgeMidpoint, .hiddenEdge: point = edge
            }
            XCTAssertLessThan(hypot(point.x - target.x, point.y - target.y), 18, "\(click)")
            store.updateAddPointer(at: point, modeID: store.addModeID)
            store.placeAddNode(at: point, modeID: store.addModeID)
            try await settle(store)
            let snapshot = try XCTUnwrap(store.snapshot)
            let created = try XCTUnwrap(snapshot.edges.first { $0.id != "crossing" })
            let endpoint = created.fromID == "anchor" ? created.toID : created.fromID
            if click == .edgeMidpoint {
                XCTAssertNotEqual(endpoint, "target")
                XCTAssertEqual(snapshot.nodes.count, 5)
                XCTAssertTrue(store.isAddingNodes)
            } else {
                XCTAssertEqual(endpoint, "target", "\(click)")
                XCTAssertEqual(snapshot.nodes.count, 4, "\(click)")
                XCTAssertFalse(store.isAddingNodes, "\(click)")
            }
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded(), "\(click)")
            XCTAssertFalse(store.canUndo, "\(click)")
        }
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Placement did not settle")
    }
}
