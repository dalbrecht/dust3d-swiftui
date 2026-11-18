import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class AddPlacementTests: XCTestCase {
    private func document(state: String = "", extraComponents: String = "") throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas originX='0.2' originY='0.3' originZ='0.4'><nodes><node id='a' partId='p' x='0' y='0' z='0.7' radius='0.1'/><node id='b' partId='p' x='1' y='1' z='0.8' radius='0.2'/><node id='c' partId='p' x='2' y='2' z='0.9' radius='0.3'/></nodes><edges><edge id='ab' partId='p' from='a' to='b'/><edge id='bc' partId='p' from='b' to='c'/></edges><parts><part id='p' \(state)/></parts><components><component id='group'><component id='component' linkData='p' linkDataType='partId'/></component>\(extraComponents)</components></canvas>"
                    .utf8))
    }
    private func projection(_ snapshot: EditorSnapshot, plane: EditingPlane = .front) -> CanvasProjection {
        .init(bounds: .init(nodes: snapshot.nodes, origin: snapshot.origin), plane: plane, width: 600, height: 400)
    }
    private func ids(_ suffix: String) -> AddPlacementIdentities {
        .init(
            nodeID: "new" + suffix, partID: "part" + suffix, componentID: "component" + suffix, edgeID: "edge" + suffix)
    }

    func testInverseProjectionAndTransientGhostUseExplicitHiddenAxisBothPlanes() throws {
        let state = try EditorState(document: document())
        let bytes = state.snapshot.document.encoded()
        for plane in EditingPlane.allCases {
            let projected = projection(state.snapshot, plane: plane)
            let position = NodePosition(x: 0.6, y: 0.8, z: 0.9)
            let hidden = plane == .front ? position.z : position.x
            let restored = try projected.position(at: projected.point(for: position), hiddenCoordinate: hidden)
            XCTAssertEqual(restored.x, position.x, accuracy: 1e-12)
            XCTAssertEqual(restored.y, position.y, accuracy: 1e-12)
            XCTAssertEqual(restored.z, position.z, accuracy: 1e-12)
            var ghost = AddPlacementState()
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            XCTAssertNil(ghost.request())
            try ghost.updatePointer(projected.point(for: position))
            XCTAssertEqual(ghost.ghostPosition?.y, 0.8)
            XCTAssertEqual(
                plane == .front ? ghost.ghostPosition?.z : ghost.ghostPosition?.x, plane == .front ? 0.4 : 0.2)
            XCTAssertEqual(ghost.sceneRadius, 32)
            try ghost.adjustRadius(by: -100)
            XCTAssertEqual(ghost.sceneRadius, 1)
            try ghost.adjustRadius(by: 500)
            XCTAssertEqual(ghost.sceneRadius, 501)
            ghost.cancel()
            XCTAssertFalse(ghost.isActive)
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            XCTAssertEqual(ghost.sceneRadius, 501)
        }
        XCTAssertEqual(state.snapshot.document.encoded(), bytes)
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testBoundaryDocumentCanBeginAndPlaceInwardWhileOutwardPointerStillRejects() throws {
        for plane in EditingPlane.allCases {
            let xml =
                "<canvas><nodes><node id='a' partId='p' x='\(plane == .front ? -1_000_000 : 0)' y='0' z='\(plane == .side ? -1_000_000 : 0)' radius='0.1'/></nodes><parts><part id='p'/></parts></canvas>"
            let state = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
            let projected = projection(state.snapshot, plane: plane)
            var ghost = AddPlacementState()
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            let inward = NodePosition(
                x: plane == .front ? -999_999.98 : 0,
                y: 0, z: plane == .side ? -999_999.98 : 0)
            try ghost.updatePointer(projected.point(for: inward))
            XCTAssertNotNil(ghost.request())
            let accepted = ghost.ghostPosition
            let outward = NodePosition(
                x: plane == .front ? -1_000_001 : 0,
                y: 0, z: plane == .side ? -1_000_001 : 0)
            XCTAssertThrowsError(try ghost.updatePointer(projected.point(for: outward)))
            XCTAssertEqual(ghost.ghostPosition, accepted)
        }
    }

    func testAnchoredInheritanceDirectionAndLocksDoNotConstrainCreation() throws {
        let original = try document()
        for (anchor, expectedFrom, expectedTo) in [("a", "newx", "a"), ("c", "c", "newx")] {
            var state = try EditorState(document: original)
            try state.select(anchor)
            for lock in EditingConstraint.allCases { state.setLock(lock, isLocked: true) }
            let projected = projection(state.snapshot)
            var ghost = AddPlacementState()
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            XCTAssertEqual(ghost.anchorID, anchor)
            try ghost.updatePointer(projected.point(for: .init(x: 3, y: 4, z: 0)))
            let inherited = try XCTUnwrap(state.snapshot.selectedNode).value.radius * 400
            XCTAssertEqual(ghost.sceneRadius, inherited)
            let request = try XCTUnwrap(ghost.request())
            _ = try state.placeAddNode(request, identities: ids("x"))
            let edge = try XCTUnwrap(state.snapshot.edges.first { $0.id == "edgex" })
            XCTAssertEqual(edge.fromID, expectedFrom)
            XCTAssertEqual(edge.toID, expectedTo)
            let node = try XCTUnwrap(state.snapshot.nodes.first { $0.id == "newx" })
            XCTAssertEqual(node.value.position.x, 3, accuracy: 1e-12)
            XCTAssertEqual(node.value.position.y, 4, accuracy: 1e-12)
            XCTAssertEqual(node.value.position.z, anchor == "a" ? 0.7 : 0.9)
            XCTAssertEqual(node.value.radius, inherited / 400)
            XCTAssertEqual(state.snapshot.selectedIDs, ["newx"])
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testExplicitRootAndWorkingGroupOverrideTransientComponentSelection() throws {
        let original = try document()
        for (destination, parentID) in [
            (AddPlacementDestination.documentRoot, nil),
            (.group("group"), "group"),
        ] {
            var state = try EditorState(document: original)
            try state.selectComponent(destination == .documentRoot ? "group" : nil)
            let projected = projection(state.snapshot)
            var ghost = AddPlacementState()
            try ghost.begin(
                snapshot: state.snapshot, projection: projected, canvasHeight: 400, destination: destination)
            try ghost.updatePointer(projected.point(for: .init(x: 3, y: 4, z: 0)))
            let request = try XCTUnwrap(ghost.request())
            _ = try state.placeAddNode(request, identities: ids("x"))
            let component = try XCTUnwrap(state.snapshot.componentTree.rows.first { $0.id == "componentx" })
            XCTAssertEqual(component.component.parentID, parentID)
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testWorkingGroupIsExactAndDoesNotReparentAnAnchoredChain() throws {
        let document = try document(extraComponents: "<component id='e\u{301}'/>")
        var state = try EditorState(document: document)
        let projected = projection(state.snapshot)
        var ghost = AddPlacementState()
        XCTAssertThrowsError(
            try ghost.begin(
                snapshot: state.snapshot, projection: projected, canvasHeight: 400, destination: .group("\u{e9}")))
        try state.select("a")
        try ghost.begin(
            snapshot: state.snapshot, projection: projected, canvasHeight: 400, destination: .group("e\u{301}"))
        try ghost.updatePointer(projected.point(for: .init(x: 3, y: 4, z: 0)))
        let request = try XCTUnwrap(ghost.request())
        XCTAssertNil(request.parentID)
        _ = try state.placeAddNode(request, identities: ids("x"))
        XCTAssertEqual(state.snapshot.nodes.last?.partID, "p")
        XCTAssertEqual(state.snapshot.componentTree.rows.first { $0.id == "component" }?.component.parentID, "group")
        XCTAssertFalse(state.snapshot.componentTree.rows.contains { $0.id == "componentx" })
    }

    func testDegreeTwoFallsBackToNewPartInsideCapturedGroup() throws {
        var state = try EditorState(document: document())
        try state.select("b")
        var ghost = AddPlacementState()
        let projected = projection(state.snapshot)
        try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400, parentID: "group")
        XCTAssertNil(ghost.anchorID)
        try ghost.updatePointer(projected.point(for: .init(x: 3, y: 4, z: 5)))
        _ = try state.placeAddNode(try XCTUnwrap(ghost.request()), identities: ids("x"))
        XCTAssertEqual(state.snapshot.nodes.last?.partID, "partx")
        XCTAssertEqual(state.snapshot.componentTree.rows.first { $0.id == "componentx" }?.component.parentID, "group")
        XCTAssertEqual(state.snapshot.edges.count, 2)
        XCTAssertEqual(state.snapshot.nodes.last?.value.position.z, 0.4)
    }

    func testSessionPlacementChainsSuppressesDuplicatesAndCancelCreatesNoHistory() async throws {
        let session = EditorSession()
        let opened = try await session.open(data: Dust3DDocument.emptyArchive())
        let projected = projection(opened)
        var ghost = AddPlacementState()
        try ghost.begin(snapshot: opened, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 0.3, y: 0.4, z: 0.5)))
        let first = try await session.placeAddNode(try XCTUnwrap(ghost.request()))
        XCTAssertTrue(first.didCommit)
        XCTAssertFalse(first.didConnect)
        try ghost.accept(first)
        XCTAssertEqual(ghost.anchorID, first.nodeID)
        let duplicate = try await session.placeAddNode(try XCTUnwrap(ghost.request()))
        XCTAssertFalse(duplicate.didCommit)
        XCTAssertEqual(duplicate.snapshot.document.encoded(), first.snapshot.document.encoded())
        try ghost.accept(duplicate)
        try ghost.updatePointer(projected.point(for: .init(x: 0.6, y: 0.7, z: 0.5)))
        let second = try await session.placeAddNode(try XCTUnwrap(ghost.request()))
        try ghost.accept(second)
        XCTAssertEqual(second.snapshot.nodes.count, 2)
        XCTAssertEqual(second.snapshot.edges.count, 1)
        ghost.cancel()
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), first.snapshot.document.encoded())
        XCTAssertTrue(undone.canUndo)
    }

    func testActorRejectsRetainedPlacementTargetsAfterFailedOpen() async throws {
        let session = EditorSession()
        let opened = try await session.open(data: Dust3DDocument.emptyArchive())
        let projected = projection(opened)
        var ghost = AddPlacementState()
        try ghost.begin(snapshot: opened, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 0.3, y: 0.4, z: 0.5)))
        let request = try XCTUnwrap(ghost.request())
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid archive opened")
        } catch {}
        do {
            _ = try await session.placeAddNode(request)
            XCTFail("Retained pointer target committed after failed open")
        } catch { XCTAssertEqual(error as? EditorError, .staleAddPlacement) }
        do {
            _ = try await session.apply(
                [
                    .addNode(
                        id: "node", partID: "part", componentID: "component",
                        position: .init(x: 0.3, y: 0.4, z: 0.5), radius: 0.1)
                ],
                selecting: "node", target: CanvasAdjustmentTarget(snapshot: opened))
            XCTFail("Retained toolbar target committed after failed open")
        } catch { XCTAssertEqual(error as? EditorError, .staleCanvasAdjustment) }
    }

    func testConnectionExitsButInvalidTargetFallsThroughToPlacement() async throws {
        let session = EditorSession()
        _ = try await session.open(data: document().encoded())
        let selected = try await session.select("a")
        let projected = projection(selected)
        var ghost = AddPlacementState()
        try ghost.begin(snapshot: selected, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 4, y: 4, z: 0)))
        let connected = try await session.placeAddNode(try XCTUnwrap(ghost.request(connectingTo: "c")))
        XCTAssertTrue(connected.didConnect)
        XCTAssertEqual(connected.snapshot.nodes.count, 3)
        try ghost.accept(connected)
        XCTAssertFalse(ghost.isActive)
        _ = try await session.undo()
        let reselected = try await session.select("a")
        try ghost.begin(snapshot: reselected, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 4, y: 4, z: 0)))
        let fallback = try await session.placeAddNode(try XCTUnwrap(ghost.request(connectingTo: "b")))
        XCTAssertFalse(fallback.didConnect)
        XCTAssertEqual(fallback.snapshot.nodes.count, 4)
    }

    func testIneligibleSelectedEndpointStartsNewPartInTheChosenGroup() throws {
        for flag in ["locked='true'", "visible='false'", "disabled='true'"] {
            let original = try document(state: flag)
            var state = try EditorState(document: original)
            try state.select("a")
            let selected = state.snapshot
            var ghost = AddPlacementState()
            let projected = projection(selected)
            try ghost.begin(snapshot: selected, projection: projected, canvasHeight: 400, destination: .group("group"))
            XCTAssertNil(ghost.anchorID, flag)
            XCTAssertEqual(state.snapshot.selectedIDs, ["a"])
            XCTAssertFalse(state.snapshot.canUndo)
            try ghost.updatePointer(projected.point(for: .init(x: 3, y: 4, z: 0.4)))
            let request = try XCTUnwrap(ghost.request())
            XCTAssertEqual(request.parentID, "group")
            XCTAssertEqual(request.position.z, 0.4, accuracy: 1e-12)
            let identities = ids("fallback")
            _ = try state.placeAddNode(request, identities: identities)
            let placed = state.snapshot
            XCTAssertEqual(placed.nodes.first { $0.id == identities.nodeID }?.partID, identities.partID)
            XCTAssertEqual(
                placed.componentTree.rows.first { $0.id == identities.componentID }?.component.parentID, "group")
            XCTAssertEqual(placed.nodes.first { $0.id == "a" }, selected.nodes.first { $0.id == "a" })
            XCTAssertEqual(placed.edges, selected.edges)
            try state.undo()
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testReadonlyAndStaleContextsRejectWithoutPublishingPartialPlacement() throws {
        for locked in [false, true] {
            var state = try EditorState(document: document(state: locked ? "locked='true'" : ""))
            try state.select("a")
            var ghost = AddPlacementState()
            let projected = projection(state.snapshot)
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            try ghost.updatePointer(projected.point(for: .init(x: 3, y: 4, z: 0)))
            let captured = try XCTUnwrap(ghost.request())
            let request =
                locked
                ? AddPlacementRequest(
                    target: captured.target, position: captured.position, radius: captured.radius, anchorID: "a",
                    parentID: nil, connectingTo: nil, lastAddedPosition: nil)
                : captured
            let before = state.snapshot
            if !locked { try state.select("b") }
            XCTAssertThrowsError(try state.placeAddNode(request, identities: ids("x"))) {
                XCTAssertEqual($0 as? EditorError, locked ? .readOnlyNode : .staleAddPlacement)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }
    func testInvalidPreviewInputsAndParentLeavePriorTransientStateUnchanged() throws {
        let state = try EditorState(document: document())
        let projected = projection(state.snapshot)
        var ghost = AddPlacementState()
        try ghost.adjustRadius(by: 10)
        XCTAssertEqual(ghost.sceneRadius, 32)
        for height in [0, -1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: height))
            XCTAssertFalse(ghost.isActive)
        }
        XCTAssertThrowsError(
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400, parentID: "component"))
        try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
        try ghost.adjustRadius(by: 10)
        XCTAssertEqual(ghost.sceneRadius, 32)
        try ghost.updatePointer(.init(x: 200, y: 200))
        let prior = ghost.ghostPosition
        XCTAssertThrowsError(try ghost.updatePointer(.init(x: .nan, y: 0)))
        XCTAssertEqual(ghost.ghostPosition, prior)
        XCTAssertThrowsError(try ghost.adjustRadius(by: .infinity))
        XCTAssertEqual(ghost.sceneRadius, 32)
        try ghost.adjustRadius(by: Double.greatestFiniteMagnitude)
        XCTAssertThrowsError(try ghost.adjustRadius(by: Double.greatestFiniteMagnitude))
        XCTAssertEqual(ghost.request()?.radius, 1)
        ghost.hideGhost()
        XCTAssertFalse(ghost.isVisible)
        XCTAssertNil(ghost.request())
        XCTAssertThrowsError(try projected.position(at: .init(x: .infinity, y: 0), hiddenCoordinate: 0.5))
        XCTAssertThrowsError(try projected.position(at: .init(x: 0, y: 0), hiddenCoordinate: 1_000_001))
        let invalidProjection = CanvasProjection(
            bounds: .init(nodes: state.snapshot.nodes), plane: .front, width: .nan, height: 400)
        XCTAssertThrowsError(try invalidProjection.position(at: .init(x: 0, y: 0), hiddenCoordinate: 0.5))
    }

    func testNewPartDefaultDepthAndCapturedGroupSelectionWorkWithoutExistingAnchor() throws {
        for selected in ["group", "component"] {
            var state = try EditorState(document: document())
            try state.selectComponent(selected)
            var ghost = AddPlacementState()
            let projected = projection(state.snapshot, plane: .side)
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            try ghost.updatePointer(projected.point(for: .init(x: 9, y: 4, z: 3)))
            XCTAssertEqual(ghost.ghostPosition?.x, 0.2)
            _ = try state.placeAddNode(try XCTUnwrap(ghost.request()), identities: ids("x"))
            XCTAssertEqual(
                state.snapshot.componentTree.rows.first { $0.id == "componentx" }?.component.parentID, "group")
        }
        let empty = try EditorState(document: Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        var ghost = AddPlacementState()
        let projected = projection(empty.snapshot, plane: .side)
        try ghost.begin(snapshot: empty.snapshot, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 1, y: 2, z: 3)))
        XCTAssertEqual(ghost.ghostPosition?.x, 0.5)
        try ghost.adjustRadius(by: -100)
        XCTAssertEqual(ghost.request()?.radius, 0.0025)
    }

    func testCrossPartConnectionConsumesTargetOwnerAndRetainsExistingJoiningPolicy() async throws {
        let source = String(decoding: try document().modelXML, as: UTF8.self)
            .replacingOccurrences(
                of: "</nodes>", with: "<node id='other' partId='q' x='3' y='3' z='3' radius='0.2'/></nodes>"
            )
            .replacingOccurrences(of: "</parts>", with: "<part id='q'/></parts>")
            .replacingOccurrences(
                of: "</components>",
                with: "<component id='othercomponent' linkData='q' linkDataType='partId'/></components>")
        let original = try Dust3DDocument(snapshotXML: Data(source.utf8))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let selected = try await session.select("a")
        var ghost = AddPlacementState()
        let projected = projection(selected)
        try ghost.begin(snapshot: selected, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 3, y: 3, z: 3)))
        let receipt = try await session.placeAddNode(try XCTUnwrap(ghost.request(connectingTo: "other")))
        XCTAssertTrue(receipt.didConnect)
        XCTAssertEqual(receipt.snapshot.nodes.count, 4)
        XCTAssertEqual(receipt.snapshot.nodes.first { $0.id == "other" }?.partID, "p")
        XCTAssertFalse(receipt.snapshot.parts.contains { $0.id == "q" })
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original.encoded())
        XCTAssertFalse(undone.canUndo)
    }

    func testRejectedConnectionPolicyFallsThroughAndRetainsItsDiagnostic() async throws {
        let source = String(decoding: try document().modelXML, as: UTF8.self)
            .replacingOccurrences(
                of: "</nodes>", with: "<node id='branch' partId='p' x='3' y='3' z='3' radius='0.2'/></nodes>"
            )
            .replacingOccurrences(
                of: "</edges>", with: "<edge id='branchEdge' partId='p' from='b' to='branch'/></edges>")
        let session = EditorSession()
        _ = try await session.open(data: Data(try Dust3DDocument(snapshotXML: Data(source.utf8)).encoded()))
        let selected = try await session.select("a")
        var ghost = AddPlacementState()
        let projected = projection(selected)
        try ghost.begin(snapshot: selected, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 4, y: 4, z: 0)))
        let receipt = try await session.placeAddNode(try XCTUnwrap(ghost.request(connectingTo: "c")))
        XCTAssertFalse(receipt.didConnect)
        XCTAssertTrue(receipt.didCommit)
        XCTAssertEqual(receipt.snapshot.nodes.count, 5)
        XCTAssertEqual(receipt.connectionFallbackReason, "invalidNode")
    }

    func testUndoReentryResetsDuplicateSuppressionAndOldReceiptsCannotRebaseLaterChains() async throws {
        let session = EditorSession()
        let original = try await session.open(data: Dust3DDocument.emptyArchive())
        let projected = projection(original)
        var ghost = AddPlacementState()
        try ghost.begin(snapshot: original, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 0.3, y: 0.4, z: 0.5)))
        let first = try await session.placeAddNode(try XCTUnwrap(ghost.request()))
        try ghost.accept(first)
        try ghost.updatePointer(projected.point(for: .init(x: 0.6, y: 0.7, z: 0.5)))
        let second = try await session.placeAddNode(try XCTUnwrap(ghost.request()))
        try ghost.accept(second)
        XCTAssertThrowsError(try ghost.accept(first))
        ghost.cancel()
        XCTAssertThrowsError(try ghost.accept(second))
        XCTAssertNil(ghost.anchorID)
        _ = try await session.undo()
        let undone = try await session.undo()
        try ghost.begin(snapshot: undone, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 0.6, y: 0.7, z: 0.5)))
        let recreated = try await session.placeAddNode(try XCTUnwrap(ghost.request()))
        XCTAssertTrue(recreated.didCommit)
        XCTAssertEqual(recreated.snapshot.nodes.count, 1)
    }

    func testIdentityAndReconstructedClickValidationRejectWithoutHistoryOrSelectionChanges() throws {
        var state = try EditorState(document: document())
        try state.select("a")
        var ghost = AddPlacementState()
        let projected = projection(state.snapshot)
        try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 3, y: 4, z: 0)))
        let request = try XCTUnwrap(ghost.request())
        let original = state.snapshot
        for invalid in [
            AddPlacementIdentities(nodeID: "group", partID: "partx", componentID: "componentx", edgeID: "edgex"),
            .init(nodeID: "", partID: "partx", componentID: "componentx", edgeID: "edgex"),
            .init(nodeID: "newx", partID: "same", componentID: "same", edgeID: "edgex"),
        ] {
            XCTAssertThrowsError(try state.placeAddNode(request, identities: invalid))
        }
        for (position, radius, anchor) in [
            (NodePosition(x: .nan, y: 0, z: 0), 0.1, "a"),
            (request.position, Double.infinity, "a"),
            (request.position, 0.0001, "a"),
            (request.position, 0.1, "missing"),
            (request.position, 0.1, "b"),
        ] {
            let reconstructed = AddPlacementRequest(
                target: request.target, position: position, radius: radius, anchorID: anchor,
                parentID: nil, connectingTo: nil, lastAddedPosition: nil)
            XCTAssertThrowsError(try state.placeAddNode(reconstructed, identities: ids("x")))
        }
        XCTAssertEqual(state.snapshot.document.encoded(), original.document.encoded())
        XCTAssertEqual(state.snapshot.selectedIDs, original.selectedIDs)
        XCTAssertEqual(state.snapshot.previewIdentity, original.previewIdentity)
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testFirstIncidentEdgeQueryTracksLiveMidpointSlotsAcrossReloadAndHistory() throws {
        let original = try document()
        XCTAssertEqual(try original.firstIncidentEdge(nodeID: "b")?.id, "ab")
        XCTAssertThrowsError(try original.firstIncidentEdge(nodeID: "missing"))
        var history = DocumentHistory(document: original)
        try history.apply(.insertEdgeMidpoint(id: "ab", nodeID: "middle", edgeID: "zz"))
        XCTAssertEqual(try history.document.firstIncidentEdge(nodeID: "b")?.id, "zz")
        XCTAssertEqual(try Dust3DDocument(data: history.document.encoded()).firstIncidentEdge(nodeID: "b")?.id, "bc")
        XCTAssertTrue(history.undo())
        XCTAssertEqual(try history.document.firstIncidentEdge(nodeID: "b")?.id, "ab")
        XCTAssertTrue(history.redo())
        XCTAssertEqual(try history.document.firstIncidentEdge(nodeID: "b")?.id, "zz")
        let isolated = try original.applying(.removeEdge(id: "ab"))
        XCTAssertNil(try isolated.firstIncidentEdge(nodeID: "a"))
    }

    func testAnchoredGhostUsesEffectiveImportedRadiusWithoutRewritingArchive() throws {
        for (sourceRadius, effective) in [("0", 0.001), ("2", 1.0)] {
            let xml = String(decoding: try document().modelXML, as: UTF8.self)
                .replacingOccurrences(of: "radius='0.1'", with: "radius='\(sourceRadius)'")
            let original = try Dust3DDocument(snapshotXML: Data(xml.utf8))
            var state = try EditorState(document: original)
            try state.select("a")
            var ghost = AddPlacementState()
            let projected = projection(state.snapshot)
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 2000)
            try ghost.updatePointer(.init(x: 200, y: 200))
            XCTAssertEqual(ghost.sceneRadius, max(1, effective * 2000))
            XCTAssertEqual(ghost.request()?.radius, effective)
            try ghost.adjustRadius(by: 5000)
            XCTAssertGreaterThan(ghost.sceneRadius, 2000)
            ghost.hideGhost()
            try ghost.updatePointer(.init(x: 210, y: 210))
            XCTAssertEqual(ghost.sceneRadius, max(1, effective * 2000))
            XCTAssertEqual(state.snapshot.document.encoded(), original.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testPlacementQuotasRejectWholeClickAndPreserveSelectedAnchorAndPreview() throws {
        for kind in ["nodes", "parts", "components", "edges"] {
            var xml = String(decoding: try document().modelXML, as: UTF8.self)
            switch kind {
            case "nodes":
                let extra = (0..<9997).map { "<node id='extra\($0)' partId='p' x='0' y='0' z='0' radius='0.1'/>" }
                    .joined()
                xml = xml.replacingOccurrences(of: "</nodes>", with: extra + "</nodes>")
            case "parts":
                let extra = (0..<9999).map { "<part id='extra\($0)'/>" }.joined()
                xml = xml.replacingOccurrences(of: "</parts>", with: extra + "</parts>")
            case "components":
                let extra = (0..<9998).map { "<component id='extra\($0)'/>" }.joined()
                xml = xml.replacingOccurrences(of: "</components>", with: extra + "</components>")
            default:
                let extra = (0..<19998).map { "<edge id='extra\($0)' partId='p' from='b' to='c'/>" }.joined()
                xml = xml.replacingOccurrences(of: "</edges>", with: extra + "</edges>")
                    .replacingOccurrences(
                        of: "</nodes>", with: "<node id='isolated' partId='p' x='3' y='3' z='3' radius='0.1'/></nodes>")
            }
            var state = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
            if kind == "nodes" || kind == "edges" { try state.select("a") }
            var ghost = AddPlacementState()
            let projected = projection(state.snapshot)
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            try ghost.updatePointer(.init(x: 200, y: 200))
            let before = state.snapshot
            for candidate: String? in kind == "edges" ? [nil, "isolated"] : [nil] {
                XCTAssertThrowsError(
                    try state.placeAddNode(try XCTUnwrap(ghost.request(connectingTo: candidate)), identities: ids("x"))
                ) {
                    XCTAssertEqual($0 as? DocumentError, .limitExceeded)
                }
                XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
                XCTAssertEqual(state.snapshot.selectedIDs, before.selectedIDs)
                XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity)
                XCTAssertFalse(state.snapshot.canUndo)
            }
        }
    }

    func testUnsupportedHierarchyAndInvalidParentCannotLeakNewPartOrSelection() throws {
        let xml = String(decoding: try document().modelXML, as: UTF8.self)
            .replacingOccurrences(of: "</components>", with: "<component id='group'/></components>")
        var malformed = try EditorState(document: Dust3DDocument(snapshotXML: Data(xml.utf8)))
        var ghost = AddPlacementState()
        let projected = projection(malformed.snapshot)
        try ghost.begin(snapshot: malformed.snapshot, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(.init(x: 200, y: 200))
        let before = malformed.snapshot.document.encoded()
        XCTAssertThrowsError(try malformed.placeAddNode(try XCTUnwrap(ghost.request()), identities: ids("x"))) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponentStructure)
        }
        XCTAssertEqual(malformed.snapshot.document.encoded(), before)
        var valid = try EditorState(document: document())
        try ghost.begin(snapshot: valid.snapshot, projection: projection(valid.snapshot), canvasHeight: 400)
        try ghost.updatePointer(.init(x: 200, y: 200))
        let request = try XCTUnwrap(ghost.request())
        let invalidParent = AddPlacementRequest(
            target: request.target, position: request.position, radius: request.radius,
            anchorID: nil, parentID: "missing", connectingTo: nil, lastAddedPosition: nil)
        XCTAssertThrowsError(try valid.placeAddNode(invalidParent, identities: ids("x")))
        XCTAssertEqual(valid.snapshot.nodes.count, 3)
        XCTAssertTrue(valid.snapshot.selectedIDs.isEmpty)
        XCTAssertFalse(valid.snapshot.canUndo)
    }

    func testModeContextTracksExternalChangesButCreationIgnoresLockEpochsAndOtherWindowsReject() async throws {
        let first = EditorSession()
        let second = EditorSession()
        let original = try document()
        _ = try await first.open(data: original.encoded())
        let selected = try await first.select("a")
        _ = try await second.open(data: original.encoded())
        var ghost = AddPlacementState()
        let projected = projection(selected)
        XCTAssertFalse(ghost.isCurrent(in: selected))
        try ghost.updatePointer(.init(x: 0, y: 0))
        try ghost.begin(snapshot: selected, projection: projected, canvasHeight: 400)
        XCTAssertTrue(ghost.isCurrent(in: selected))
        try ghost.updatePointer(.init(x: 200, y: 200))
        let request = try XCTUnwrap(ghost.request())
        do {
            _ = try await second.placeAddNode(request)
            XCTFail("Other windows must reject")
        } catch { XCTAssertEqual(error as? EditorError, .staleAddPlacement) }
        for lock in EditingConstraint.allCases { _ = try await first.setLock(lock, isLocked: true) }
        let placed = try await first.placeAddNode(request)
        XCTAssertTrue(placed.didCommit)
        XCTAssertFalse(ghost.isCurrent(in: placed.snapshot))
        try ghost.accept(placed)
        XCTAssertTrue(ghost.isCurrent(in: placed.snapshot))
        let savedRadius = ghost.sceneRadius
        ghost.cancel()
        try ghost.begin(snapshot: placed.snapshot, projection: projected, canvasHeight: 400)
        XCTAssertEqual(ghost.sceneRadius, savedRadius)
        let changed = try await first.select("c")
        XCTAssertFalse(ghost.isCurrent(in: changed))
    }

    func testAlreadyConnectedEndpointsFallThroughToNewNodeForEitherDirection() throws {
        let original = try document().applying(.removeEdge(id: "bc"))
        for (anchor, target) in [("a", "b"), ("b", "a")] {
            var state = try EditorState(document: original)
            try state.select(anchor)
            var ghost = AddPlacementState()
            let projected = projection(state.snapshot)
            try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
            try ghost.updatePointer(.init(x: 200, y: 200))
            let result = try state.placeAddNode(
                try XCTUnwrap(ghost.request(connectingTo: target)), identities: ids("x"))
            XCTAssertEqual(result.outcome, .placed(nodeID: "newx"))
            XCTAssertEqual(state.snapshot.nodes.count, 4)
            XCTAssertEqual(state.snapshot.edges.count, 2)
            XCTAssertEqual(state.snapshot.edges.first { $0.id == "ab" }?.fromID, "a")
        }
    }

    func testAbsentOriginFallbackAndSideAnchorHiddenAxisAreExplicit() throws {
        let empty = try EditorState(
            document: Dust3DDocument(snapshotXML: Data("<canvas><nodes/><edges/><parts/><components/></canvas>".utf8)))
        for plane in EditingPlane.allCases {
            var ghost = AddPlacementState()
            let projected = projection(empty.snapshot, plane: plane)
            try ghost.begin(snapshot: empty.snapshot, projection: projected, canvasHeight: 400)
            try ghost.updatePointer(projected.point(for: .init(x: 2, y: 3, z: 4)))
            XCTAssertEqual(plane == .front ? ghost.ghostPosition?.z : ghost.ghostPosition?.x, 0.5)
        }
        var state = try EditorState(document: document())
        try state.select("c")
        var ghost = AddPlacementState()
        let projected = projection(state.snapshot, plane: .side)
        try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(projected.point(for: .init(x: 99, y: 3, z: 4)))
        XCTAssertEqual(ghost.ghostPosition?.x, 2)
        _ = try state.placeAddNode(try XCTUnwrap(ghost.request()), identities: ids("x"))
        XCTAssertEqual(state.snapshot.nodes.last?.value.position.x, 2)
        XCTAssertEqual(try XCTUnwrap(state.snapshot.nodes.last).value.position.z, 4, accuracy: 1e-12)
    }

    func testInconsistentPlacementReceiptCannotReplaceCurrentGhostAnchor() throws {
        let state = try EditorState(document: document())
        var ghost = AddPlacementState()
        let projected = projection(state.snapshot)
        try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 400)
        try ghost.updatePointer(.init(x: 200, y: 200))
        let request = try XCTUnwrap(ghost.request())
        let receipt = AddPlacementReceipt(
            snapshot: state.snapshot, outcome: .placed(nodeID: "missing"),
            contextID: request.contextID, connectionFallbackReason: nil)
        let before = ghost.ghostPosition
        XCTAssertThrowsError(try ghost.accept(receipt))
        XCTAssertNil(ghost.anchorID)
        XCTAssertEqual(ghost.ghostPosition, before)
        XCTAssertTrue(ghost.isActive)
    }

    func testWouldCommitRadiusSharesRequestClampWhileRawPreviewRemainsUnbounded() throws {
        let state = try EditorState(document: document())
        var ghost = AddPlacementState()
        XCTAssertNil(ghost.wouldCommitRadius)
        let projected = projection(state.snapshot)
        try ghost.begin(snapshot: state.snapshot, projection: projected, canvasHeight: 4000)
        XCTAssertNil(ghost.wouldCommitRadius)
        try ghost.updatePointer(.init(x: 200, y: 200))
        try ghost.adjustRadius(by: -100)
        XCTAssertEqual(ghost.sceneRadius, 1)
        XCTAssertEqual(ghost.wouldCommitRadius, 0.001)
        XCTAssertEqual(ghost.request()?.radius, ghost.wouldCommitRadius)
        try ghost.adjustRadius(by: 8000)
        XCTAssertEqual(ghost.sceneRadius, 8001)
        XCTAssertEqual(ghost.wouldCommitRadius, 1)
        XCTAssertEqual(ghost.request()?.radius, ghost.wouldCommitRadius)
        ghost.hideGhost()
        XCTAssertNil(ghost.wouldCommitRadius)
    }

}
