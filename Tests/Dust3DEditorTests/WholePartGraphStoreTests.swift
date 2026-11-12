import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor final class WholePartGraphStoreTests: XCTestCase {
    private let a = "{11111111-1111-4111-8111-111111111111}"
    private let b = "{22222222-2222-4222-8222-222222222222}"
    private let c = "{33333333-3333-4333-8333-333333333333}"
    private let d = "{44444444-4444-4444-8444-444444444444}"
    private let p = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private let q = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
    private let edge = "{55555555-5555-4555-8555-555555555555}"
    private let otherEdge = "{66666666-6666-4666-8666-666666666666}"
    private let group = "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}"
    private let component = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
    private func document(locked: Bool = false) throws -> Dust3DDocument {
        let precedingRows = (0..<8).map {
            "<component id='{77777777-7777-4777-8777-77777777777\($0)}' name='Folder \($0)'/>"
        }.joined()
        return try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='\(a)' partId='\(p)' x='0' y='0' z='0' radius='.1'/>
                <node id='\(b)' partId='\(p)' x='1' y='1' z='1' radius='.2'/>
                <node id='\(c)' partId='\(q)' x='3' y='0' z='3' radius='.1'/>
                <node id='\(d)' partId='\(q)' x='4' y='1' z='4' radius='.2'/>
                </nodes><edges><edge id='\(edge)' partId='\(p)' from='\(a)' to='\(b)'/>
                <edge id='\(otherEdge)' partId='\(q)' from='\(c)' to='\(d)'/></edges>
                <parts><part id='\(p)' locked='\(locked)'/><part id='\(q)'/></parts><components>
                <component id='\(group)' name='Group'>\(precedingRows)<component id='\(component)' name='First part' linkDataType='partId' linkData='\(p)'/></component>
                <component id='{dddddddd-dddd-4ddd-8ddd-dddddddddddd}' name='Second part' linkDataType='partId' linkData='\(q)'/>
                </components></canvas>
                """.utf8))
    }
    func testWholePartSelectsExplicitEdgesOnceWithoutDocumentPreviewHistoryAndEnablesBatchCommands() async throws {
        let source = try document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let revision = try XCTUnwrap(store.snapshot).selectionRevision
        let preview = store.previewRevision
        store.selectWholePart(.part(p))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [a, b])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edge])
        XCTAssertEqual(store.snapshot?.selectionRevision, revision + 1)
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, [])
        XCTAssertNil(store.snapshot?.selectedPartID)
        XCTAssertEqual(store.snapshot?.componentRevealHint?.componentID, component)
        XCTAssertEqual(store.snapshot?.componentRevealHint?.ancestorIDs, [group])
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertEqual(store.previewRevision, preview)
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(store.canReverseSelectedEdges)
        XCTAssertTrue(store.canInsertEdgeMidpoint)
        store.reverseExplicitlySelectedEdges()
        store.selectWholePart(.part(q))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [a, b], "Whole-part actions do not queue behind graph mutations")
        XCTAssertEqual(store.snapshot?.edges.first { $0.id == edge }?.fromID, b)
        XCTAssertEqual(store.snapshot?.edges.first { $0.id == otherEdge }?.fromID, c)
        store.undo()
        try await settle(store)
        store.insertSelectedEdgeMidpoints()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 5)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edge])
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        store.selectPartNodes(p)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [a, b])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
    }
    func testDoubleClickIntentionSurvivesSinglePickInFlightAndReadonlyRemainsInspectable() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document(locked: true)
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(a)
        store.selectWholePart(.node(a))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [a, b])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edge])
        XCTAssertFalse(store.canReverseSelectedEdges)
        XCTAssertFalse(store.canInsertEdgeMidpoint)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(store.canUndo)
        for plane in [EditingPlane.front, .side] {
            let projection = CanvasProjection(bounds: store.bounds, plane: plane, width: 500, height: 300)
            let point = projection.point(for: .init(x: 3.5, y: 0.5, z: 3.5))
            store.selectWholePart(at: point, projection: projection)
            try await settle(store)
            XCTAssertEqual(store.snapshot?.selectedIDs, [c, d])
            XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [otherEdge])
        }
        let beforeBlank = store.snapshot?.selectionRevision
        store.selectWholePart(
            at: .init(x: -5000, y: -5000),
            projection: .init(bounds: store.bounds, plane: .front, width: 500, height: 300))
        XCTAssertEqual(store.snapshot?.selectionRevision, beforeBlank)
    }
    func testSidebarRemountDoesNotReplayAnAlreadyHandledReveal() async throws {
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: try document().encoded())
        try await settle(store)
        let disclosure = ComponentSidebarDisclosure(collapsedIDs: [group, "unrelated"])
        store.selectWholePart(.edge(edge))
        try await settle(store)
        let snapshot = try XCTUnwrap(store.snapshot)
        let hint = try XCTUnwrap(snapshot.componentRevealHint)

        disclosure.reveal(hint, documentIdentity: snapshot.documentIdentity)
        XCTAssertEqual(disclosure.collapsedIDs, ["unrelated"])
        disclosure.collapsedIDs.insert(group)
        let manualEpoch = disclosure.epoch
        disclosure.reveal(hint, documentIdentity: snapshot.documentIdentity)
        XCTAssertEqual(disclosure.collapsedIDs, [group, "unrelated"])
        XCTAssertEqual(disclosure.epoch, manualEpoch)

        store.selectWholePart(.edge(edge))
        try await settle(store)
        let newHint = try XCTUnwrap(store.snapshot?.componentRevealHint)
        disclosure.reveal(newHint, documentIdentity: snapshot.documentIdentity)
        XCTAssertEqual(disclosure.collapsedIDs, ["unrelated"])
    }

    func testRevealExpandsAncestorsWithoutComponentSelectionOrGraphReplacement() async throws {
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: try document().encoded())
        try await settle(store)
        let disclosure = ComponentSidebarDisclosure(collapsedIDs: [group, "unrelated"])
        let host = NSHostingView(
            rootView: VStack(alignment: .leading, spacing: 0) { ComponentSidebar(store: store, disclosure: disclosure) }
                .frame(width: 300, height: 240))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 300, height: 240), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        window.contentView = host
        host.frame = .init(x: 0, y: 0, width: 300, height: 240)
        store.selectWholePart(.edge(edge))
        try await settle(store)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(disclosure.collapsedIDs, ["unrelated"])
        host.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(findTable(in: host))
        let ownerIndex = try XCTUnwrap(
            store.snapshot?.componentTree.visibleRows(collapsing: disclosure.collapsedIDs).firstIndex {
                $0.id == component
            })
        XCTAssertTrue(
            NSLocationInRange(ownerIndex, table.rows(in: table.visibleRect)),
            "Reveal scrolls the owner into the 120-point native list viewport")
        XCTAssertEqual(store.snapshot?.selectedIDs, [a, b])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edge])
        XCTAssertEqual(store.snapshot?.selectedComponentIDs, [])
        let hintRevision = store.snapshot?.componentRevealHint?.revision
        store.selectWholePart(.edge(edge))
        try await settle(store)
        XCTAssertNotEqual(store.snapshot?.componentRevealHint?.revision, hintRevision)
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("ui-qa/whole-part")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let freshDisclosure = ComponentSidebarDisclosure(collapsedIDs: [group])
        let freshHost = NSHostingView(
            rootView: VStack(alignment: .leading, spacing: 0) {
                ComponentSidebar(store: store, disclosure: freshDisclosure)
            }.frame(width: 300, height: 240).background(Color(nsColor: .windowBackgroundColor)).environment(
                \.colorScheme, .light))
        let freshWindow = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 300, height: 240), styleMask: [], backing: .buffered, defer: false)
        freshWindow.isReleasedWhenClosed = false
        freshWindow.appearance = NSAppearance(named: .aqua)
        freshHost.appearance = freshWindow.appearance
        defer {
            freshWindow.contentView = nil
            freshWindow.close()
        }
        freshWindow.contentView = freshHost
        freshHost.frame = .init(x: 0, y: 0, width: 300, height: 240)
        freshHost.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        freshHost.layoutSubtreeIfNeeded()
        let freshTable = try XCTUnwrap(findTable(in: freshHost))
        XCTAssertTrue(
            NSLocationInRange(ownerIndex, freshTable.rows(in: freshTable.visibleRect)),
            "A newly mounted sidebar also reveals an existing hint")
        let bitmap = try XCTUnwrap(freshHost.bitmapImageRepForCachingDisplay(in: freshHost.bounds))
        freshHost.cacheDisplay(in: freshHost.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("revealed-component.png"))
    }
    func testNativeClickCountTwoSuppressesDragAndLaterSinglePickWhileAddPressKeepsPrecedence() throws {
        let node = NodePointerView(frame: .init(x: 0, y: 0, width: 36, height: 36))
        node.enabled = true
        node.canDrag = true
        var began = 0
        var singles = 0
        var whole = 0
        node.begin = { _ in began += 1 }
        node.select = { singles += 1 }
        node.doubleClick = { whole += 1 }
        for count in [1, 2] {
            node.mouseDown(with: try event(.leftMouseDown, count: count))
            node.mouseUp(with: try event(.leftMouseUp, count: count))
        }
        XCTAssertEqual(began, 1)
        XCTAssertEqual(singles, 1)
        XCTAssertEqual(whole, 1)
        let canvas = CanvasPointerView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        canvas.enabled = true
        var canvasSingles = 0
        var doubles = 0
        var placements = 0
        canvas.tap = { _, _ in canvasSingles += 1 }
        canvas.doubleClick = { _ in doubles += 1 }
        canvas.addPress = { _ in placements += 1 }
        for count in [1, 2] {
            canvas.mouseDown(with: try event(.leftMouseDown, count: count))
            canvas.mouseUp(with: try event(.leftMouseUp, count: count))
        }
        XCTAssertEqual(canvasSingles, 1)
        XCTAssertEqual(doubles, 1)
        canvas.isAddingNodes = true
        canvas.mouseDown(with: try event(.leftMouseDown, count: 2))
        canvas.mouseUp(with: try event(.leftMouseUp, count: 2))
        XCTAssertEqual(placements, 1)
        XCTAssertEqual(doubles, 1)
    }
    func testHostedRealDoubleSequenceSurvivesSingleSelectionAndRetainedCallbacksRejectNewDocumentsAndMutation()
        async throws
    {
        let source = try document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        let host = NSHostingView(rootView: NodeCanvas(store: store))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 500, height: 300), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        host.frame = .init(x: 0, y: 0, width: 500, height: 300)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 300)
        let point = projection.point(for: try XCTUnwrap(store.snapshot?.nodes.first { $0.id == a }).value.position)
        let hit = try XCTUnwrap(host.hitTest(.init(x: point.x, y: 300 - point.y)) as? NodePointerView)
        let nodeDouble = try XCTUnwrap(hit.doubleClick)
        let canvas = try XCTUnwrap(findCanvas(in: host))
        let backgroundDouble = try XCTUnwrap(canvas.doubleClick)
        for count in [1, 2] {
            let down = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: .leftMouseDown, location: .init(x: point.x, y: 300 - point.y), modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count,
                    pressure: 1))
            let up = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: .leftMouseUp, location: .init(x: point.x, y: 300 - point.y), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1))
            hit.mouseDown(with: down)
            hit.mouseUp(with: up)
        }
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [a, b])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edge])
        let changed = try source.applying(.setNode(id: a, position: .init(x: 10, y: 2, z: 8), radius: 0.1))
        await store.load(data: changed.encoded())
        try await settle(store)
        nodeDouble()
        backgroundDouble(point)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertNil(store.snapshot?.componentRevealHint)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let freshCanvas = try XCTUnwrap(findCanvas(in: host))
        let freshBackgroundDouble = try XCTUnwrap(freshCanvas.doubleClick)
        let freshContext = PartGraphSelectionContext(snapshot: try XCTUnwrap(store.snapshot))
        store.edit(id: a, position: .init(x: 11, y: 2, z: 8), radius: 0.1)
        try await settle(store)
        let before = store.snapshot?.selectionRevision
        store.selectWholePart(.node(a), context: freshContext)
        freshBackgroundDouble(point)
        XCTAssertEqual(store.snapshot?.selectionRevision, before)
        XCTAssertEqual(store.snapshot?.selectedIDs, [a])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
    }
    func testRenderedPartNodeAndEdgeActionsKeepCapturedContextIncludingMissingRenderedDocument() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let missingRenderedAction = store.wholePartSelectionAction(.part(p))
        let missingNodesAction = store.partNodesSelectionAction(p)
        await store.load(data: try document().encoded())
        try await settle(store)
        let partAction = store.wholePartSelectionAction(.part(p))
        let nodesAction = store.partNodesSelectionAction(p)
        let edgeAction = store.wholePartSelectionAction(.edge(edge))
        let nodeAction = store.wholePartSelectionAction(.node(a))
        store.select(a)
        store.selectWholePart(.node(a))
        await store.load(data: try document().encoded())
        try await settle(store)
        let revision = store.snapshot?.selectionRevision
        missingRenderedAction()
        missingNodesAction()
        nodesAction()
        partAction()
        edgeAction()
        nodeAction()
        XCTAssertEqual(store.snapshot?.selectionRevision, revision)
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertNil(store.snapshot?.componentRevealHint)
        XCTAssertFalse(store.canUndo)
    }
    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.findTable(in: $0) }.first
    }
    private func findCanvas(in view: NSView) -> CanvasPointerView? {
        if let canvas = view as? CanvasPointerView { return canvas }
        return view.subviews.lazy.compactMap { self.findCanvas(in: $0) }.first
    }
    private func event(_ type: NSEvent.EventType, count: Int) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: .init(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 1, clickCount: count, pressure: 1))
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Whole-part selection did not settle")
    }
}
