import CoreGraphics
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

private actor HeldAddReferenceImage: ReferenceImageServing {
    let image: CGImage
    private var pending: CheckedContinuation<Void, Never>?
    private var released = false

    init(image: CGImage) { self.image = image }

    func importImage(url: URL) async throws -> Data { throw CancellationError() }

    func preview(document: Dust3DDocument) async throws -> ReferenceImagePreview {
        if !released {
            await withCheckedContinuation { pending = $0 }
        }
        return .init(image: image, changed: true)
    }

    func release() {
        released = true
        pending?.resume()
        pending = nil
    }
}

@MainActor final class AddProfileTransferStoreTests: XCTestCase {
    func testQtDepthOptInCommitsPreviewThenKeepsTheNewAnchorDepthAndUndoesExactly() async throws {
        let original = Dust3DDocument.emptyArchive()
        let stub = AddProfileTransferNoNative()
        let store = EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer { store.stop() }
        await store.load(data: original)
        store.setDualCanvasProfile(true)
        store.setQtOppositeProfileDepth(true)
        let front = CanvasProjection(bounds: store.bounds, plane: .front, width: 420, height: 240)
        store.setCanvasContext(projection: front, width: 420, height: 240, lease: store.canvasProfiles.lease)
        store.beginAddMode()
        let firstPoint = front.point(for: .init(x: 0.25, y: 0.5, z: 0))
        let mode = store.addModeID
        store.updateAddPointer(at: firstPoint, modeID: mode)
        let preview = try XCTUnwrap(store.qtAddDepthGuidePosition)
        XCTAssertEqual(preview.z, 0.75, accuracy: 1e-12)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        store.placeAddNode(at: firstPoint, modeID: mode)
        try await settle(store)
        let committed = try XCTUnwrap(store.snapshot?.nodes.first?.value.position)
        XCTAssertEqual(committed.x, preview.x, accuracy: 1e-12)
        XCTAssertEqual(committed.y, preview.y, accuracy: 1e-12)
        XCTAssertEqual(committed.z, preview.z, accuracy: 1e-12)

        let secondPoint = front.point(for: .init(x: 0.65, y: 0.5, z: 0))
        store.updateAddPointer(at: secondPoint, modeID: mode)
        XCTAssertEqual(try XCTUnwrap(store.addPlacement.ghostPosition).z, preview.z, accuracy: 1e-12)
        store.placeAddNode(at: secondPoint, modeID: mode)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 2)
        store.undo()
        try await settle(store)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testQtDepthWaitsForAcceptedEmbeddedAspect() async throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 3, height: 1, bitsPerComponent: 8, bytesPerRow: 12,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let png = try ReferenceImageCodec.encodePNG(image)
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
            .applying(.setReferenceImagePNG(png)).encoded()
        let stub = AddProfileTransferNoNative()
        let reference = HeldAddReferenceImage(image: image)
        let store = EditorStore(
            referenceImages: reference, preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
        defer {
            store.stop()
            Task { await reference.release() }
        }
        await store.load(data: original)
        store.setDualCanvasProfile(true)
        func installGeometry() -> CanvasProjection {
            let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 420, height: 240)
            store.setCanvasContext(projection: projection, width: 420, height: 240, lease: store.canvasProfiles.lease)
            return projection
        }
        _ = installGeometry()
        XCTAssertTrue(store.canBeginAddMode)
        store.setQtOppositeProfileDepth(true)
        XCTAssertTrue(store.isLoadingReferenceImage)
        XCTAssertTrue(store.qtOppositeProfileDepthNeedsReference)
        XCTAssertFalse(store.canBeginAddMode)
        store.beginAddMode()
        XCTAssertFalse(store.isAddingNodes)
        await reference.release()
        for _ in 0..<300 where store.isLoadingReferenceImage {
            try await Task.sleep(for: .milliseconds(10))
        }
        let front = installGeometry()
        XCTAssertTrue(store.canBeginAddMode)
        store.beginAddMode()
        store.updateAddPointer(at: front.point(for: .init(x: 0.25, y: 0.5, z: 0)), modeID: store.addModeID)
        XCTAssertEqual(try XCTUnwrap(store.qtAddDepthGuidePosition).z, 1, accuracy: 1e-12)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

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

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Placement did not settle")
    }
}
