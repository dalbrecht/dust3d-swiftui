import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor final class ReferenceColorStoreTests: XCTestCase {
    private let a = "{11111111-1111-4111-8111-111111111111}"
    private let b = "{22222222-2222-4222-8222-222222222222}"
    private let edge = "{44444444-4444-4444-8444-444444444444}"
    private func document(image: Bool = true) throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        document = try document.applying(
            .addNode(
                id: a, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.1, y: 0.1, z: 0.1),
                radius: 0.1))
        document = try document.applying(
            .addNode(
                id: b, partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: nil, position: .init(x: 0.3, y: 0.2, z: 0.3), radius: 0.1))
        document = try document.applying(.addEdge(id: edge, from: a, to: b))
        if image {
            let data = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(ReferenceColorPNGFixtures.orientations[1])))
            document = try document.applying(.setReferenceImagePNG(data))
        }
        return document
    }
    private func context(_ store: EditorStore, width: Double = 400, height: Double = 300) {
        store.setReferenceColorCanvasContext(
            projection: .init(
                bounds: store.bounds, plane: store.plane,
                width: width, height: height), width: width, height: height)
    }
    func testPairedDisplayedRasterExplicitNodeAdmissionAtomicHistoryAndClearWithoutImage() async throws {
        let source = try document()
        let first = EditorStore()
        let second = EditorStore()
        defer {
            first.stop()
            second.stop()
        }
        for store in [first, second] {
            await store.load(data: source.encoded())
            try await settle(store)
            context(store)
            try await settle(store)
            store.selectEdges([edge])
            try await settle(store)
            XCTAssertFalse(store.canAutoColorSelection)
            XCTAssertFalse(store.canClearSelectionColors)
            store.selectGraph(nodes: [a], edges: [edge])
            try await settle(store)
        }
        XCTAssertTrue(first.canAutoColorSelection)
        XCTAssertNotNil(first.fittedReferenceColorImage)
        first.autoColorSelection()
        try await settle(first)
        XCTAssertNil(first.errorMessage)
        XCTAssertTrue(first.canUndo)
        XCTAssertNotEqual(first.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(second.snapshot?.document.encoded(), source.encoded())
        let previewIdentity = first.snapshot?.previewIdentity
        first.autoColorSelection()
        try await settle(first)
        XCTAssertEqual(first.referenceColorNotice, "No part colors changed.")
        XCTAssertEqual(first.snapshot?.previewIdentity, previewIdentity)
        first.undo()
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(first.canUndo)
        let noImage = try document(image: false).applying(
            .setComponentColor(id: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", color: .init(red: 1, green: 2, blue: 3)))
        await first.load(data: noImage.encoded())
        try await settle(first)
        first.select(a)
        try await settle(first)
        XCTAssertFalse(first.canAutoColorSelection)
        XCTAssertTrue(first.canClearSelectionColors)
        first.clearSelectionColors()
        try await settle(first)
        XCTAssertTrue(first.canUndo)
    }
    func testHiddenPendingResizeAndRetainedActionsCannotColorWrongContext() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        context(store)
        try await settle(store)
        store.select(a)
        try await settle(store)
        let old = store.referenceColorAction()
        store.plane = .side
        old()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        context(store, width: 700)
        try await settle(store)
        store.showsReferenceImage = false
        XCTAssertFalse(store.canAutoColorSelection)
        XCTAssertTrue(store.canClearSelectionColors)
        let clear = store.clearSelectionColorsAction()
        await store.load(data: source.encoded())
        try await settle(store)
        clear()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
    }
    func testQueuedApplyCancellationBeforeCommitAndReceiptAfterCommit() async throws {
        for afterCommit in [false, true] {
            let gate = GatedReferenceColorApplication(afterCommit: [1: afterCommit])
            let store = EditorStore(referenceColorApplying: gate)
            defer { store.stop() }
            let source = try document()
            await store.load(data: source.encoded())
            try await settle(store)
            context(store)
            try await settle(store)
            store.select(a)
            try await settle(store)
            store.autoColorSelection()
            await gate.waitUntilEntered(1)
            let task = store.referenceColorCommitTask
            store.plane = .side
            context(store, width: 700, height: 350)
            await gate.release(1)
            await task?.value
            try await settle(store)
            XCTAssertEqual(store.canUndo, afterCommit)
            if afterCommit {
                XCTAssertNotEqual(store.snapshot?.document.encoded(), source.encoded())
                store.undo()
                try await settle(store)
            }
            XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        }
    }
    func testOldCompletionCannotClearNewApplyCancellationMarkerOrNotice() async throws {
        let gate = GatedReferenceColorApplication(afterCommit: [1: true, 2: false])
        let store = EditorStore(referenceColorApplying: gate)
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        context(store)
        try await settle(store)
        store.select(a)
        try await settle(store)
        store.autoColorSelection()
        await gate.waitUntilEntered(1)
        let oldTask = store.referenceColorCommitTask
        await store.load(data: source.encoded())
        try await settle(store)
        context(store)
        try await settle(store)
        store.select(a)
        try await settle(store)
        store.autoColorSelection()
        await gate.waitUntilEntered(2)
        let currentTask = store.referenceColorCommitTask
        await gate.release(1)
        await oldTask?.value
        XCTAssertTrue(store.isWorking)
        XCTAssertNil(store.referenceColorNotice)
        store.plane = .side
        context(store, width: 500)
        await gate.release(2)
        await currentTask?.value
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertNil(store.referenceColorNotice)
    }
    func testDisabledActionAndLayoutAwayAndBackArePermanentlyStale() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(a)
        try await settle(store)
        let disabled = store.referenceColorAction()
        context(store)
        try await settle(store)
        XCTAssertTrue(store.canAutoColorSelection)
        disabled()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        let old = store.referenceColorAction()
        context(store, width: 700)
        try await settle(store)
        context(store)
        try await settle(store)
        old()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
    }
    func testReadonlyMutationAvailabilityUsesActualEdgeOwnerAndCapturedContextPayload() async throws {
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let source = try document().applying(.setPartState(id: part, property: .locked, value: true))
        let store = EditorStore(preview: ReferenceColorNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        context(store)
        try await settle(store)
        store.selectGraph(nodes: [a], edges: [edge])
        try await settle(store)
        let disabled = GraphColorizeActions(store: store)
        XCTAssertFalse(disabled.canClear)
        XCTAssertFalse(disabled.canAutoColor)
        let q = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
        let cq = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        let xml = String(decoding: source.modelXML, as: UTF8.self)
            .replacingOccurrences(of: "</parts>", with: "<part id='\(q)'/></parts>")
            .replacingOccurrences(
                of: "</components>", with: "<component id='\(cq)' linkDataType='partId' linkData='\(q)'/></components>"
            )

        let model = try XMLDocument(data: Data(xml.utf8))
        let edges = try XCTUnwrap(model.rootElement()?.elements(forName: "edges").first)
        let ownedEdge = try XCTUnwrap(edges.elements(forName: "edge").first)
        try XCTUnwrap(ownedEdge.attribute(forName: "partId")).stringValue = q
        var mixed = try Dust3DDocument(snapshotXML: model.xmlData)
        mixed = try mixed.applying(.setReferenceImagePNG(XCTUnwrap(source.referenceImagePNG)))
        await store.load(data: mixed.encoded())
        try await settle(store)
        context(store)
        try await settle(store)
        store.selectGraph(nodes: [a], edges: [edge])
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdges.first?.partID, q)
        let actions = GraphColorizeActions(store: store)
        XCTAssertFalse(actions.canClear)
        XCTAssertTrue(actions.canAutoColor)
        disabled.autoColor()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
        actions.autoColor()
        try await settle(store)
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.referenceColorNotice?.contains("read-only") == true)
    }
    func testFractionalLogicalFitDisplaysSourceAspectInsteadOfRoundedRasterAspect() async throws {
        let data = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(ReferenceColorPNGFixtures.orientations[6])))
        let source = try document().applying(.setReferenceImagePNG(data))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let projection = CanvasProjection(
            bounds: .init(nodes: [], referenceImageAspectRatio: 1.5),
            plane: .front, width: 1000, height: 74.1)
        XCTAssertEqual(projection.scale, 2.1, accuracy: 1e-12)
        store.setReferenceColorCanvasContext(projection: projection, width: 1000, height: 74.1)
        try await settle(store)
        let image = try XCTUnwrap(store.fittedReferenceColorImage)
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 3)
        XCTAssertEqual(try XCTUnwrap(store.referenceColorDisplayAspect), 1.5)
        XCTAssertNotEqual(Double(image.width) / Double(image.height), store.referenceColorDisplayAspect)
    }
    func testResizeCoalescesPendingRasterAndStopRejectsLatePreparedImage() async throws {
        let service = HeldReferenceColorRaster()
        let store = EditorStore(referenceColorRaster: service)
        defer { store.stop() }
        await store.load(data: try document().encoded())
        try await settle(store)
        store.select(a)
        try await settle(store)
        context(store, width: 400)
        context(store, width: 700)
        await service.waitUntilEntered(1)
        let count = await service.callCount
        XCTAssertEqual(count, 1, "Same-turn resize requests coalesce before raster decoding")
        XCTAssertFalse(store.canAutoColorSelection)
        let pending = store.referenceColorPreparation
        store.stop()
        await service.release(1)
        await pending?.value
        XCTAssertNil(store.fittedReferenceColorImage)
        XCTAssertFalse(store.isPreparingReferenceColors)
        XCTAssertFalse(store.canAutoColorSelection)
        XCTAssertFalse(store.canUndo)
    }
    func testUnsupportedPreparationPreservesCauseAndInteractionEpochCannotReviveOldActions() async throws {
        let unsupported = EditorStore(referenceColorRaster: UnsupportedReferenceColorRaster())
        defer { unsupported.stop() }
        await unsupported.load(data: try document().encoded())
        try await settle(unsupported)
        unsupported.select(a)
        try await settle(unsupported)
        context(unsupported)
        try await settle(unsupported)
        XCTAssertFalse(unsupported.canAutoColorSelection)
        XCTAssertTrue(unsupported.canClearSelectionColors)
        XCTAssertTrue(unsupported.referenceColorError?.contains("profile") == true)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: try document().encoded())
        try await settle(store)
        context(store)
        try await settle(store)
        store.select(a)
        try await settle(store)
        let actions = GraphColorizeActions(store: store)
        store.setReferenceColorInteractionActive(true)
        XCTAssertFalse(store.canAutoColorSelection)
        XCTAssertFalse(store.canClearSelectionColors)
        store.setReferenceColorInteractionActive(false)
        actions.autoColor()
        actions.clear()
        try await settle(store)
        XCTAssertFalse(store.canUndo)
    }
    func testHostedShiftPointerInvalidatesRetainedColorActionsAcrossRelease() async throws {
        _ = NSApplication.shared
        let source = try document().applying(
            .setComponentColor(
                id: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                color: try XCTUnwrap(DocumentColor(archiveValue: "#123456"))))
        let store = EditorStore(preview: ReferenceColorNoPreview())
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectGraph(nodes: [a, b], edges: [])
        try await settle(store)
        let host = NSHostingView(rootView: NodeCanvas(store: store))
        host.frame = .init(x: 0, y: 0, width: 472, height: 472)
        let window = NSWindow(
            contentRect: .init(x: -10000, y: -10000, width: 472, height: 472),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if store.canAutoColorSelection && store.canClearSelectionColors { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.canAutoColorSelection)
        XCTAssertTrue(store.canClearSelectionColors)
        let retained = GraphColorizeActions(store: store)
        let before = try XCTUnwrap(store.snapshot)
        let projection = CanvasProjection(bounds: store.bounds, plane: store.plane, width: 472, height: 472)
        let point = projection.point(for: try source.node(id: a).position)
        let start = NSPoint(x: point.x, y: 472 - point.y)
        let hit = try XCTUnwrap(host.hitTest(start) as? NodePointerView)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: start, modifierFlags: .shift,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                    pressure: 1))
        }
        hit.mouseDown(with: try event(.leftMouseDown))
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            if !store.canAutoColorSelection && !store.canClearSelectionColors { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(store.canAutoColorSelection)
        XCTAssertFalse(store.canClearSelectionColors)
        hit.mouseUp(with: try event(.leftMouseUp))
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if store.canAutoColorSelection && store.canClearSelectionColors { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.canAutoColorSelection)
        XCTAssertTrue(store.canClearSelectionColors)
        XCTAssertEqual(store.snapshot?.selectionRevision, before.selectionRevision)
        retained.clear()
        retained.autoColor()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testHostedColorizeControlsAndSharedContextMenuPayloadRender() async throws {
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: try document().encoded())
        try await settle(store)
        context(store)
        try await settle(store)
        store.selectGraph(nodes: [a], edges: [edge])
        try await settle(store)
        let actions = GraphColorizeActions(store: store)
        XCTAssertTrue(actions.canAutoColor)
        XCTAssertTrue(actions.canClear)
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("ui-qa/reference-color")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            try InspectorRenderer.png(
                VStack {
                    GraphColorizeControls(store: store)
                    GraphColorizeMenu(actions: actions)
                }, width: 330, scheme: scheme
            )
            .write(to: directory.appendingPathComponent("colorize-\(scheme == .light ? "light" : "dark").png"))
        }
    }
    func testLateOldSourceRasterCannotBecomeInputAfterImageReplacement() async throws {
        let service = HeldReferenceColorRaster()
        let store = EditorStore(referenceColorRaster: service)
        defer { store.stop() }
        let original = try document()
        await store.load(data: original.encoded())
        try await settle(store)
        context(store)
        await service.waitUntilEntered(1)
        let old = store.referenceColorPreparation
        let png = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(ReferenceColorPNGFixtures.orientations[2])))
        let replacement = try original.applying(.setReferenceImagePNG(png))
        await store.load(data: replacement.encoded())
        await service.waitUntilEntered(2)
        await service.release(1)
        await old?.value
        XCTAssertNil(store.fittedReferenceColorImage)
        XCTAssertFalse(store.canAutoColorSelection)
        let current = store.referenceColorPreparation
        await service.release(2)
        await current?.value
        try await settle(store)
        store.select(a)
        try await settle(store)
        XCTAssertTrue(store.canAutoColorSelection)
        store.autoColorSelection()
        try await settle(store)
        let component = try XCTUnwrap(store.snapshot?.componentTree.rows.first?.component)
        guard case .value(let color) = component.color else { return XCTFail("Expected sampled override") }
        XCTAssertEqual(color.red, 12, "Only the replacement orientation's first source pixel may be sampled")
        XCTAssertEqual(color.alpha, 255)
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials && !store.isLoadingReferenceImage
                && !store.isPreparingReferenceColors
            {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Reference colors did not settle")
    }
}

private actor GatedReferenceColorApplication: ReferenceColorApplying {
    private let afterCommit: [Int: Bool]
    private var next = 0
    private var entered: Set<Int> = []
    private var awaitingEntry: [Int: CheckedContinuation<Void, Never>] = [:]
    private var held: [Int: CheckedContinuation<Void, Never>] = [:]
    init(afterCommit: [Int: Bool]) { self.afterCommit = afterCommit }
    func waitUntilEntered(_ id: Int) async {
        if entered.contains(id) { return }
        await withCheckedContinuation { awaitingEntry[id] = $0 }
    }
    func release(_ id: Int) { held.removeValue(forKey: id)?.resume() }
    private func suspend(_ id: Int) async {
        await withCheckedContinuation { continuation in
            held[id] = continuation
            entered.insert(id)
            awaitingEntry.removeValue(forKey: id)?.resume()
        }
    }
    func apply(
        raster: ReferenceColorRaster, layout: ReferenceColorSamplingLayout, referencePNG: Data,
        target: ReferenceColorTarget, in session: EditorSession
    ) async throws -> ReferenceColorReceipt {
        next += 1
        let id = next
        if afterCommit[id] == true {
            let receipt = try await session.autoColorSelectedParts(
                raster: raster, layout: layout,
                referencePNG: referencePNG, target: target)
            await suspend(id)
            return receipt
        }
        await suspend(id)
        try Task.checkCancellation()
        return try await session.autoColorSelectedParts(
            raster: raster, layout: layout,
            referencePNG: referencePNG, target: target)
    }
}

private struct ReferenceColorNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

private actor HeldReferenceColorRaster: ReferenceColorRasterServing {
    private(set) var callCount = 0
    private var entered: Set<Int> = []
    private var entryWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    func waitUntilEntered(_ id: Int) async {
        if entered.contains(id) { return }
        await withCheckedContinuation { entryWaiters[id] = $0 }
    }
    func release(_ id: Int) { pending.removeValue(forKey: id)?.resume() }
    func prepare(document: Dust3DDocument, logicalHeight: Double) async throws -> ReferenceColorRasterResult {
        callCount += 1
        let id = callCount
        let result = try ReferenceColorRasterCodec.prepare(document: document, logicalHeight: logicalHeight)
        await withCheckedContinuation { continuation in
            pending[id] = continuation
            entered.insert(id)
            entryWaiters.removeValue(forKey: id)?.resume()
        }
        return result  // Deliberately return after cancellation to exercise the store publication guard.
    }
}
private struct UnsupportedReferenceColorRaster: ReferenceColorRasterServing {
    func prepare(document: Dust3DDocument, logicalHeight: Double) async throws -> ReferenceColorRasterResult {
        throw ReferenceColorRasterError.unsupportedDisplayProfile
    }
}
