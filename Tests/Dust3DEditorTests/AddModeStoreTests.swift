import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor final class AddModeStoreTests: XCTestCase {
    func testTransientGhostRadiusPressPlacementAndChainingUseFrozenProjectionAndOneUndoEach() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 300)
        store.setCanvasContext(projection: projection, width: 500, height: 300)
        store.beginAddMode()
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertNil(store.addGhostPoint)
        let epoch = store.addModeID
        store.placeAddNode(at: .init(x: 200, y: 150), modeID: epoch)
        XCTAssertFalse(store.isWorking)
        store.updateAddPointer(at: .init(x: 200, y: 150), modeID: epoch)
        XCTAssertEqual(store.addGhostRadius, 32)
        store.adjustSelectionRadius(direction: 1)
        XCTAssertTrue(store.handleCanvasWheel(.init(verticalDelta: -1, modifiers: .command)))
        XCTAssertEqual(store.addGhostRadius, 32)
        XCTAssertNotEqual(projection.scale, 300)
        let displayDiameterBeforePlacement = store.addGhostDisplayDiameter
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        let boundsBefore = projection.point(for: .init(x: 0.5, y: 0.5, z: 0.5))
        store.placeAddNode(at: .init(x: 200, y: 150), modeID: epoch)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 1)
        XCTAssertTrue(store.isAddingNodes)
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.nodes.first).value.radius, 32.0 / 300, accuracy: 1e-12)
        XCTAssertEqual(store.frozenAddProjection?.point(for: .init(x: 0.5, y: 0.5, z: 0.5)), boundsBefore)
        XCTAssertEqual(
            displayDiameterBeforePlacement,
            try XCTUnwrap(store.snapshot?.nodes.first).value.radius * projection.scale * 2, accuracy: 1e-12)
        let nextPoint = CanvasPoint(x: 330, y: 210)
        store.updateAddPointer(at: nextPoint, modeID: epoch)
        store.adjustSelectionRadius(direction: 1)
        let requestedRadius = store.addGhostModelRadius
        let anchorID = store.addPlacement.anchorID
        let resizedProjection = CanvasProjection(bounds: store.bounds, plane: .front, width: 600, height: 360)
        let previousProjection = try XCTUnwrap(store.frozenAddProjection)
        store.setCanvasContext(projection: previousProjection, width: 600, height: 360)
        guard store.isAddingNodes else {
            XCTFail("Resizing must retain the active Add chain")
            return
        }
        XCTAssertEqual(store.addPlacement.anchorID, anchorID)
        XCTAssertEqual(store.frozenAddProjection, resizedProjection)
        XCTAssertEqual(store.addGhostModelRadius, requestedRadius, accuracy: 1e-12)
        XCTAssertNil(store.addGhostPoint)
        XCTAssertFalse(store.canPlaceAddGhost)
        let resizedEpoch = store.addModeID
        XCTAssertNotEqual(resizedEpoch, epoch)
        store.updateAddPointer(at: nextPoint, modeID: epoch)
        store.placeAddNode(at: nextPoint, modeID: epoch)
        XCTAssertNil(store.addGhostPoint)
        XCTAssertFalse(store.isWorking)
        store.updateAddPointer(at: nextPoint, modeID: resizedEpoch)
        XCTAssertEqual(store.addGhostModelRadius, requestedRadius, accuracy: 1e-12)
        let anchor = try XCTUnwrap(store.snapshot?.nodes.first { $0.id == anchorID })
        let expectedPosition = try resizedProjection.position(at: nextPoint, hiddenCoordinate: anchor.value.position.z)
        store.placeAddNode(at: nextPoint, modeID: resizedEpoch)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 2)
        let added = try XCTUnwrap(store.snapshot?.nodes.first { $0.id != anchorID })
        XCTAssertEqual(added.partID, anchor.partID)
        XCTAssertEqual(added.value.radius, requestedRadius, accuracy: 1e-12)
        XCTAssertEqual(added.value.position.x, expectedPosition.x, accuracy: 1e-12)
        XCTAssertEqual(added.value.position.y, expectedPosition.y, accuracy: 1e-12)
        XCTAssertEqual(added.value.position.z, expectedPosition.z, accuracy: 1e-12)
        XCTAssertEqual(store.snapshot?.edges.count, 1)
        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(store.mesh)
        XCTAssertFalse(store.previewState.isStale)
        store.updateAddPointer(at: .init(x: 350, y: 210), modeID: store.addModeID)
        try render(store)
        store.undo()
        try await settle(store)
        XCTAssertFalse(store.isAddingNodes)
        XCTAssertEqual(store.snapshot?.nodes.count, 1)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
    }
    func testContextCancellationRejectsOldCallbacksAndGhostInputDoesNotEditSelectedNode() async throws {
        var source = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        source = try source.applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.2))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(store.snapshot?.nodes.first?.id)
        try await settle(store)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 200)
        store.setCanvasContext(projection: projection, width: 400, height: 200)
        store.beginAddMode()
        let oldEpoch = store.addModeID
        store.updateAddPointer(at: .init(x: 220, y: 100), modeID: oldEpoch)
        store.adjustSelectionRadius(direction: -1)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.plane = .side
        XCTAssertFalse(store.isAddingNodes)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: .side, width: 400, height: 200), width: 400, height: 200)
        store.beginAddMode()
        store.updateAddPointer(at: .init(x: 250, y: 100), modeID: oldEpoch)
        store.placeAddNode(at: .init(x: 250, y: 100), modeID: oldEpoch)
        XCTAssertNil(store.addGhostPoint)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.cancelAddMode()
        XCTAssertFalse(store.canUndo)
    }
    func testNativeAddPressPlacesOnMouseDownAndNoSelectionOnMouseUp() throws {
        let view = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        view.enabled = true
        view.isAddingNodes = true
        var presses = 0
        var selections = 0
        view.addPress = { _ in presses += 1 }
        view.tap = { _, _ in selections += 1 }
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .init(x: 20, y: 30), modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: .init(x: 20, y: 30), modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        XCTAssertEqual(presses, 1)
        view.mouseUp(with: up)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(selections, 0)
    }
    func testCancellationBeforeCommitCreatesNothingAndAfterCommitStillPublishesActorTruth() async throws {
        for (beforeCommit, resizes) in [(true, false), (false, false), (true, true), (false, true)] {
            let service = GatedAddPlacementService(beforeCommit: beforeCommit)
            let store = EditorStore(addPlacements: service)
            defer { store.stop() }
            let original = Dust3DDocument.emptyArchive()
            await store.load(data: original)
            try await settle(store)
            let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 300)
            store.setCanvasContext(projection: projection, width: 400, height: 300)
            store.beginAddMode()
            store.updateAddPointer(at: .init(x: 200, y: 150), modeID: store.addModeID)
            store.placeAddNode(at: .init(x: 200, y: 150), modeID: store.addModeID)
            await service.waitUntilBlocked()
            if resizes {
                store.setCanvasContext(projection: projection, width: 450, height: 300)
            } else {
                store.cancelAddMode()
            }
            await service.release()
            try await settle(store)
            XCTAssertFalse(store.isAddingNodes)
            XCTAssertEqual(store.snapshot?.nodes.count, beforeCommit ? 0 : 1)
            XCTAssertEqual(store.canUndo, !beforeCommit)
            if !beforeCommit {
                store.undo()
                try await settle(store)
                XCTAssertEqual(store.snapshot?.document.encoded(), original)
            }
        }
    }
    func testCommittedReceiptFromReplacedDocumentCannotOverwriteNewDocument() async throws {
        let service = GatedAddPlacementService(beforeCommit: false)
        let store = EditorStore(addPlacements: service)
        defer { store.stop() }
        let original = Dust3DDocument.emptyArchive()
        await store.load(data: original)
        try await settle(store)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: .front, width: 400, height: 300), width: 400, height: 300)
        store.beginAddMode()
        store.updateAddPointer(at: .init(x: 200, y: 150), modeID: store.addModeID)
        store.placeAddNode(at: .init(x: 200, y: 150), modeID: store.addModeID)
        await service.waitUntilBlocked()
        await store.load(data: original)
        let newIdentity = store.snapshot?.documentIdentity
        await service.release()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.documentIdentity, newIdentity)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }
    func testSelectionCancellationRefitsNewlyPlacedNodeAfterFrozenAddBounds() async throws {
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: Dust3DDocument.emptyArchive())
        try await settle(store)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: .front, width: 400, height: 300),
            width: 400, height: 300)
        store.beginAddMode()
        let point = CanvasPoint(x: 380, y: 150)
        store.updateAddPointer(at: point, modeID: store.addModeID)
        store.placeAddNode(at: point, modeID: store.addModeID)
        try await settle(store)
        XCTAssertTrue(store.isAddingNodes)
        let node = try XCTUnwrap(store.snapshot?.nodes.first)
        store.select(nil)
        try await settle(store)
        XCTAssertFalse(store.isAddingNodes)
        let projected = CanvasProjection(bounds: store.bounds, plane: .front, width: 400, height: 300)
        XCTAssertLessThanOrEqual(projected.point(for: node.value.position).x, 364)
        XCTAssertEqual(store.snapshot?.nodes.count, 1)
    }

    func testOldPlacementCompletionCannotUnmarkAndUncancelNewDocumentPlacement() async throws {
        let service = ReplacedAddPlacementService()
        let store = EditorStore(addPlacements: service)
        defer { store.stop() }
        let original = Dust3DDocument.emptyArchive()
        func startPlacement() {
            store.setCanvasContext(
                projection: .init(bounds: store.bounds, plane: .front, width: 400, height: 300),
                width: 400, height: 300)
            store.beginAddMode()
            store.updateAddPointer(at: .init(x: 200, y: 150), modeID: store.addModeID)
            store.placeAddNode(at: .init(x: 200, y: 150), modeID: store.addModeID)
        }
        await store.load(data: original)
        try await settle(store)
        startPlacement()
        await service.waitUntilBlocked(0)
        await store.load(data: original)
        try await settle(store)
        let identity = store.snapshot?.documentIdentity
        startPlacement()
        await service.waitUntilBlocked(1)
        await service.release(0)
        // Let the old perform task unwind while the current service remains deterministically gated.
        try await Task.sleep(for: .milliseconds(100))
        store.cancelAddMode()
        await service.release(1)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.documentIdentity, identity)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testFreshPlaneProjectionAndToolExclusivityDoNotMutateArchive() async throws {
        let source = Dust3DDocument.emptyArchive()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source)
        try await settle(store)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: .front, width: 400, height: 300), width: 400, height: 300)
        store.plane = .side
        store.setMovingOrigin(true)
        XCTAssertTrue(store.isMovingOrigin)
        store.beginAddMode()
        XCTAssertFalse(store.isMovingOrigin)
        XCTAssertEqual(store.frozenAddProjection?.plane, .side)
        store.setMovingOrigin(true)
        XCTAssertFalse(store.isAddingNodes)
        XCTAssertTrue(store.isMovingOrigin)
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
    }
    func testConnectionExitsAndRejectedJoinFallbackCommitsWithOriginalDiagnostic() async throws {
        for rejectedTarget in [false, true] {
            var source = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
            let a = "{11111111-1111-4111-8111-111111111111}"
            let b = "{22222222-2222-4222-8222-222222222222}"
            let p = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
            let q = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
            source = try source.applying(
                .addNode(
                    id: a, partID: p, componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                    position: .init(x: 0.2, y: 0.4, z: 0.6), radius: 0.1))
            source = try source.applying(
                .addNode(
                    id: b, partID: rejectedTarget ? q : p,
                    componentID: rejectedTarget ? "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}" : nil,
                    position: .init(x: 0.8, y: 0.6, z: 0.6), radius: 0.2))
            if rejectedTarget {
                source = try source.applying(
                    .addNode(
                        id: "{33333333-3333-4333-8333-333333333333}", partID: q, componentID: nil,
                        position: .init(x: 1.4, y: 0.6, z: 0.6), radius: 0.1))
            }
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: source.encoded())
            try await settle(store)
            store.select(a)
            try await settle(store)
            let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 300)
            store.setCanvasContext(projection: projection, width: 500, height: 300)
            store.beginAddMode()
            let point = projection.point(for: try XCTUnwrap(store.snapshot?.nodes.first { $0.id == b }).value.position)
            store.updateAddPointer(at: point, modeID: store.addModeID)
            store.placeAddNode(at: point, modeID: store.addModeID)
            try await settle(store)
            XCTAssertEqual(store.snapshot?.nodes.count, rejectedTarget ? 4 : 2)
            XCTAssertEqual(store.snapshot?.edges.count, 1)
            XCTAssertEqual(store.isAddingNodes, rejectedTarget)
            XCTAssertEqual(store.addPlacementNotice != nil, rejectedTarget)
            XCTAssertNil(store.errorMessage)
            store.undo()
            try await settle(store)
            XCTAssertNil(store.addPlacementNotice)
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
            XCTAssertFalse(store.canUndo)
        }
    }
    func testSelectedGroupDestinationAndAccessiblePreviewControlsCreateNoHistoryUntilPlacement() async throws {
        let group = "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}"
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='\(group)' name='Group' combineMode='Normal'/></components></canvas>"
                    .utf8))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectComponent(group)
        try await settle(store)
        store.setCanvasContext(
            projection: .init(bounds: store.bounds, plane: .front, width: 500, height: 300), width: 500, height: 300)
        store.beginAddMode()
        store.previewAddAtCanvasCenter()
        store.nudgeAddPreview(x: 16, y: 0)
        XCTAssertEqual(store.addGhostPoint, .init(x: 266, y: 150))
        XCTAssertFalse(store.canUndo)
        store.placeAddNode(at: try XCTUnwrap(store.addGhostPoint), modeID: store.addModeID)
        try await settle(store)
        let part = try XCTUnwrap(store.snapshot?.nodes.first?.partID)
        XCTAssertEqual(
            store.snapshot?.componentTree.rows.first { $0.component.partID == part }?.component.parentID, group)
    }
    func testHostedAddPressOwnsNodeHitAndOldHeldNodeAndMarqueeCannotEditAfterToolSwitch() async throws {
        var source = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let a = "{11111111-1111-4111-8111-111111111111}"
        source = try source.applying(
            .addNode(
                id: a, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(a)
        try await settle(store)
        let host = NSHostingView(rootView: NodeCanvas(store: store))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 472, height: 472), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        host.frame = window.contentView?.bounds ?? .init(x: 0, y: 0, width: 472, height: 472)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 472, height: 472)
        let center = projection.point(for: try XCTUnwrap(store.snapshot?.nodes.first).value.position)
        let hitPoint = NSPoint(x: center.x, y: 472 - center.y)
        let node = try XCTUnwrap(host.hitTest(hitPoint) as? NodePointerView)
        let oldCanvas = try XCTUnwrap(findCanvas(in: host))
        node.mouseDown(with: try event(.leftMouseDown, point: hitPoint, window: window))
        node.mouseDragged(
            with: try event(.leftMouseDragged, point: .init(x: hitPoint.x + 20, y: hitPoint.y), window: window))
        oldCanvas.mouseDown(with: try event(.leftMouseDown, point: .init(x: 30, y: 30), window: window))
        store.beginAddMode()
        node.mouseUp(with: try event(.leftMouseUp, point: .init(x: hitPoint.x + 40, y: hitPoint.y), window: window))
        oldCanvas.mouseUp(with: try event(.leftMouseUp, point: .init(x: 400, y: 400), window: window))
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.snapshot?.selectedIDs, [a])
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let addCanvas = try XCTUnwrap(host.hitTest(hitPoint) as? CanvasPointerView)
        let placement = NSPoint(x: hitPoint.x + 80, y: hitPoint.y + 40)
        let down = try event(.leftMouseDown, point: placement, window: window)
        addCanvas.mouseMoved(with: down)
        addCanvas.mouseDown(with: down)
        XCTAssertTrue(store.isWorking, "Placement starts on press without mouseUp")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 2)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(store.isAddingNodes)
        XCTAssertTrue(store.canUndo)
    }
    func testHeldNodePressAcrossAddModeRoundTripCannotToggleSelectionOnRelease() async throws {
        var source = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        source = try source.applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}",
                partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                position: .init(x: 0.5, y: 0.5, z: 0.5), radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(nil)
        try await settle(store)
        let initialSelection = store.snapshot?.selectedIDs
        let host = NSHostingView(rootView: NodeCanvas(store: store).frame(width: 472, height: 472))
        let window = NSWindow(
            contentRect: .init(x: -10000, y: -10000, width: 472, height: 472),
            styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let projection = CanvasProjection(bounds: store.bounds, plane: store.plane, width: 472, height: 472)
        let point = projection.point(for: .init(x: 0.5, y: 0.5, z: 0.5))
        let hitPoint = NSPoint(x: point.x, y: 472 - point.y)
        let node = try XCTUnwrap(host.hitTest(hitPoint) as? NodePointerView)
        func commandEvent(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: hitPoint, modifierFlags: .command,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                    clickCount: 1, pressure: 1))
        }
        node.mouseDown(with: try commandEvent(.leftMouseDown))
        store.beginAddMode()
        XCTAssertTrue(store.isAddingNodes)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        store.cancelAddMode()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        node.mouseUp(with: try commandEvent(.leftMouseUp))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, initialSelection)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func findCanvas(in view: NSView) -> CanvasPointerView? {
        if let canvas = view as? CanvasPointerView { return canvas }
        return view.subviews.lazy.compactMap { self.findCanvas(in: $0) }.first
    }
    private func event(_ type: NSEvent.EventType, point: NSPoint, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    func testUnboundedRequestedPreviewDisclosesCommittedRadiusLimitsWithoutEditingUntilPress() async throws {
        for height in [20.0, 2000.0] {
            let source = Dust3DDocument.emptyArchive()
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: source)
            try await settle(store)
            store.setCanvasContext(
                projection: .init(bounds: store.bounds, plane: .front, width: 400, height: height), width: 400,
                height: height)
            store.beginAddMode()
            store.previewAddAtCanvasCenter()
            if height == 2000 { for _ in 0..<31 { store.adjustSelectionRadius(direction: -1) } }
            let requested = store.addGhostRadius
            XCTAssertEqual(requested, height == 20 ? 32 : 1)
            XCTAssertNotNil(store.addRadiusLimitNotice)
            XCTAssertEqual(store.snapshot?.document.encoded(), source)
            XCTAssertFalse(store.canUndo)
            if height == 20 {
                for _ in 0..<13 { store.adjustSelectionRadius(direction: -1) }
                XCTAssertNil(store.addRadiusLimitNotice)
                for _ in 0..<13 { store.adjustSelectionRadius(direction: 1) }
            } else {
                store.adjustSelectionRadius(direction: 1)
                XCTAssertNil(store.addRadiusLimitNotice)
                store.adjustSelectionRadius(direction: -1)
            }
            XCTAssertEqual(store.addGhostRadius, requested)
            store.placeAddNode(at: try XCTUnwrap(store.addGhostPoint), modeID: store.addModeID)
            try await settle(store)
            XCTAssertEqual(store.snapshot?.nodes.first?.value.radius, height == 20 ? 1 : 0.001)
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), source)
            XCTAssertFalse(store.canUndo)
        }
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Add mode did not settle")
    }
    private func render(_ store: EditorStore) throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("ui-qa/add-mode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ghost = store.addGhostPoint ?? .init(x: 350, y: 210)
        for scheme in [ColorScheme.light, .dark] {
            if !store.isAddingNodes {
                store.setCanvasContext(
                    projection: .init(bounds: store.bounds, plane: store.plane, width: 500, height: 300), width: 500,
                    height: 300)
                store.beginAddMode()
                store.updateAddPointer(at: ghost, modeID: store.addModeID)
            }
            let data = try InspectorRenderer.png(
                VStack {
                    AddModeControls(store: store)
                    NodeCanvas(store: store).frame(width: 500, height: 300)
                }, width: 532, scheme: scheme)
            try data.write(to: directory.appendingPathComponent("ghost-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}

private actor GatedAddPlacementService: AddPlacementServing {
    let beforeCommit: Bool
    private var isBlocked = false
    private var blockedWaiter: CheckedContinuation<Void, Never>?
    private var releasePlacement: CheckedContinuation<Void, Never>?
    init(beforeCommit: Bool) { self.beforeCommit = beforeCommit }
    func place(_ request: AddPlacementRequest, in session: EditorSession) async throws -> AddPlacementReceipt {
        if beforeCommit {
            await pause()
            try Task.checkCancellation()
        }
        let receipt = try await session.placeAddNode(request)
        if !beforeCommit { await pause() }
        return receipt
    }
    private func pause() async {
        await withCheckedContinuation { continuation in
            releasePlacement = continuation
            isBlocked = true
            blockedWaiter?.resume()
            blockedWaiter = nil
        }
    }
    func waitUntilBlocked() async {
        if isBlocked { return }
        await withCheckedContinuation { blockedWaiter = $0 }
    }
    func release() {
        releasePlacement?.resume()
        releasePlacement = nil
    }
}

private actor ReplacedAddPlacementService: AddPlacementServing {
    private var nextIndex = 0
    private var releases: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    func place(_ request: AddPlacementRequest, in session: EditorSession) async throws -> AddPlacementReceipt {
        let index = nextIndex
        nextIndex += 1
        if index == 0 {
            let receipt = try await session.placeAddNode(request)
            await pause(index)
            return receipt
        }
        await pause(index)
        try Task.checkCancellation()
        return try await session.placeAddNode(request)
    }
    private func pause(_ index: Int) async {
        await withCheckedContinuation { continuation in
            releases[index] = continuation
            waiters.removeValue(forKey: index)?.resume()
        }
    }
    func waitUntilBlocked(_ index: Int) async {
        if releases[index] != nil { return }
        await withCheckedContinuation { waiters[index] = $0 }
    }
    func release(_ index: Int) { releases.removeValue(forKey: index)?.resume() }
}
