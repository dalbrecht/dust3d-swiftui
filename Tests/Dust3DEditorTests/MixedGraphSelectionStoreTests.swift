import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class MixedGraphSelectionStoreTests: XCTestCase {
    private let ids = (1...4).map { "{00000000-0000-4000-8000-00000000000\($0)}" }
    private let edges = (1...3).map { "{11111111-1111-4111-8111-11111111111\($0)}" }
    private let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"

    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ids.enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: part,
                    componentID: index == 0 ? "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}" : nil,
                    position: .init(x: Double(index), y: Double(index % 2), z: Double(index)), radius: 0.1))
        }
        for index in 0..<3 {
            document = try document.applying(.addEdge(id: edges[index], from: ids[index], to: ids[index + 1]))
        }
        return document
    }

    func testExplicitSubsetBatchCommandsRetainSelectionsAndOneHistoryStepPerWindow() async throws {
        let original = try document()
        let store = EditorStore()
        let other = EditorStore()
        defer {
            store.stop()
            other.stop()
        }
        await store.load(data: original.encoded())
        await other.load(data: original.encoded())
        try await settle(store)
        try await settle(other)
        store.selectGraph(nodes: Set(ids), edges: [edges[1]])
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edges[1]])
        XCTAssertTrue(store.canReverseSelectedEdges)
        XCTAssertTrue(store.canTransformSelection(.exchangeXZ))
        try render(store, name: "mixed")
        store.reverseExplicitlySelectedEdges()
        XCTAssertFalse(store.canReverseSelectedEdges)
        XCTAssertFalse(store.canTransformSelection(.flipX))
        XCTAssertFalse(store.canTransformSelection(.exchangeXZ))
        try await settle(store)
        XCTAssertEqual(store.snapshot?.edges.first { $0.id == edges[0] }?.fromID, ids[0])
        XCTAssertEqual(store.snapshot?.edges.first { $0.id == edges[1] }?.fromID, ids[2])
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        store.selectGraph(nodes: [ids[0]], edges: Set(edges.prefix(2)))
        try await settle(store)
        XCTAssertNil(store.snapshot?.selectedEdgeID)
        XCTAssertTrue(store.canInsertEdgeMidpoint)
        let revision = store.previewRevision
        store.insertSelectedEdgeMidpoints()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, Set(edges.prefix(2)))
        XCTAssertEqual(store.snapshot?.selectedIDs, [ids[0]])
        XCTAssertEqual(store.snapshot?.nodes.count, 6)
        XCTAssertNotNil(store.mesh)
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertGreaterThan(store.previewRevision, revision)
        XCTAssertNil(store.errorMessage)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        store.selectEdges(Set(edges.prefix(2)))
        try await settle(store)
        XCTAssertFalse(store.canCopyNodes)
        XCTAssertFalse(store.canCutNodes)
        XCTAssertTrue(store.canTransform)
        XCTAssertFalse(store.canTransformSelection(.exchangeXZ))
        XCTAssertTrue(store.canTransformSelection(.flipX))
        XCTAssertTrue(store.canTransformSelection(.originFrontX))
        try render(store, name: "edge-group")
        store.selectGraph(nodes: [ids[1]], edges: Set(edges.prefix(2)))
        try await settle(store)
        XCTAssertTrue(store.canDeleteGraphSelection)
        store.deleteSelection()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 3)
        XCTAssertEqual(store.snapshot?.edges.map(\.id), [edges[2]])
        XCTAssertEqual(store.snapshot?.selectedIDs, [])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)

    }

    func testCanvasProjectionAddToggleAndReadonlyAvailability() async throws {
        let original = try document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectGraph(nodes: [ids[0]], edges: [])
        try await settle(store)
        for plane in [EditingPlane.front, .side] {
            let projection = CanvasProjection(bounds: store.bounds, plane: plane, width: 500, height: 500)
            let point = projection.point(for: .init(x: 1.5, y: 0.5, z: 1.5))
            store.pickEdge(at: point, projection: projection, mode: .add)
            try await settle(store)
        }
        XCTAssertEqual(store.snapshot?.selectedIDs, [ids[0]])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edges[1]])
        store.toggleEdgeSelection(edges[1])
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
        XCTAssertEqual(store.snapshot?.selectedIDs, [ids[0]])
        store.toggleSelection(ids[1])
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, Set(ids.prefix(2)))
        let locked = try original.applying(.setPartState(id: part, property: .locked, value: true))
        await store.load(data: locked.encoded())
        try await settle(store)
        store.selectEdges(Set(edges.prefix(2)))
        try await settle(store)
        XCTAssertFalse(store.canReverseSelectedEdges)
        XCTAssertFalse(store.canInsertEdgeMidpoint)
        XCTAssertFalse(store.canDeleteGraphSelection)
        try render(store, name: "locked")
    }

    func testMarqueeSelectsCrossingEdgesExplicitlyWithoutInferringEndpointEdges() async throws {
        let original = try document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectGraph(nodes: [ids[0]], edges: [])
        try await settle(store)
        for plane in [EditingPlane.front, .side] {
            let projection = CanvasProjection(bounds: store.bounds, plane: plane, width: 500, height: 500)
            let center = projection.point(for: .init(x: 1.5, y: 0.5, z: 1.5))
            let rectangle = CanvasSelectionRectangle(
                from: .init(x: center.x - 2, y: center.y - 2), to: .init(x: center.x + 2, y: center.y + 2))
            store.selectMarquee(rectangle, projection: projection, mode: .add)
            try await settle(store)
        }
        XCTAssertEqual(store.snapshot?.selectedIDs, [ids[0]])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [edges[1]])
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 500)
        let center = projection.point(for: .init(x: 1.5, y: 0.5, z: 1.5))
        store.selectMarquee(
            .init(from: .init(x: center.x - 2, y: center.y - 2), to: .init(x: center.x + 2, y: center.y + 2)),
            projection: projection, mode: .toggle)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [ids[0]])
        XCTAssertEqual(store.snapshot?.selectedEdgeIDs, [])
    }

    func testTransformAvailabilityRequiresOriginOnlyForOriginCommands() async throws {
        let model = try XMLDocument(data: document().modelXML)
        for name in ["originX", "originY", "originZ"] { model.rootElement()?.removeAttribute(forName: name) }
        let source = try Dust3DDocument(snapshotXML: model.xmlData())
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectEdges([edges[1]])
        try await settle(store)
        XCTAssertTrue(store.canTransformSelection(.flipX))
        XCTAssertFalse(store.canTransformSelection(.originFrontX))
        XCTAssertFalse(store.canTransformSelection(.exchangeXZ))
    }

    func testSelectionChangesRejectStaleCanvasDragWithoutChangingDocument() async throws {
        let original = try document()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectGraph(nodes: [ids[0]], edges: [edges[0]])
        try await settle(store)
        let snapshot = try XCTUnwrap(store.snapshot)
        let projection = CanvasProjection(bounds: store.bounds, plane: .front, width: 500, height: 500)
        let drag = try NodeDrag(anchorID: ids[0], snapshot: snapshot, projection: projection)
        store.toggleEdgeSelection(edges[1])
        try await settle(store)
        store.commitNodeDrag(drag, translation: .init(x: 10, y: 0))
        try await settle(store)
        XCTAssertEqual(store.errorMessage, EditorStore.message(EditorError.staleNodeDrag))
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testMixedCutCopiesOnlyExplicitNodeDeletesRemoteEdgeAndRejectsReadonlyBeforeWriting() async throws {
        var original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let secondPart = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
        for (index, id) in ids.enumerated() {
            original = try original.applying(
                .addNode(
                    id: id, partID: index < 2 ? part : secondPart,
                    componentID: index == 0 || index == 2 ? "{cccccccc-cccc-4ccc-8ccc-ccccccccccc\(index)}" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        for index in [0, 2] {
            original = try original.applying(.addEdge(id: edges[index], from: ids[index], to: ids[index + 1]))
        }
        let store = EditorStore()
        defer { store.stop() }
        let pasteboard = RecordingMixedClipboard()
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectGraph(nodes: [ids[0]], edges: [edges[2]])
        try await settle(store)
        XCTAssertTrue(store.canCutNodes)
        pasteboard.shouldFail = true
        store.copyNodes(cut: true, to: pasteboard)
        try await settle(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(pasteboard.writeCount, 0)
        pasteboard.shouldFail = false
        store.copyNodes(cut: true, to: pasteboard)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        let xml = try XCTUnwrap(pasteboard.snapshotXML)
        let payload = try Dust3DDocument(snapshotXML: xml).editorContents()
        XCTAssertEqual(payload.nodes.map(\.id), [ids[0]])
        XCTAssertTrue(payload.edges.isEmpty)
        XCTAssertEqual(store.snapshot?.nodes.count, 3)
        XCTAssertTrue(store.snapshot?.edges.isEmpty == true)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
        let locked = try original.applying(.setPartState(id: secondPart, property: .locked, value: true))
        await store.load(data: locked.encoded())
        try await settle(store)
        store.selectGraph(nodes: [ids[0]], edges: [edges[2]])
        try await settle(store)
        XCTAssertFalse(store.canCutNodes)
        let changeCount = pasteboard.writeCount
        store.copyNodes(cut: true, to: pasteboard)
        XCTAssertEqual(pasteboard.writeCount, changeCount)
        XCTAssertEqual(store.snapshot?.document.encoded(), locked.encoded())
    }

    private func render(_ store: EditorStore, name: String) throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("ui-qa/mixed-selection")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let data = try InspectorRenderer.png(
                VStack(alignment: .leading) {
                    EdgeSidebar(store: store)
                    Divider()
                    GraphSelectionInspector(store: store)
                }, width: 320, scheme: scheme)
            try data.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
            if name == "mixed" {
                let canvas = try InspectorRenderer.png(
                    NodeCanvas(store: store).frame(height: 360), width: 500, scheme: scheme)
                try canvas.write(
                    to: directory.appendingPathComponent("canvas-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<400 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Mixed selection did not settle")
    }
}

@MainActor private final class RecordingMixedClipboard: EditorClipboardWriting {
    private(set) var snapshotXML: Data?
    private(set) var writeCount = 0
    var shouldFail = false
    func write(_ data: Data, snapshotXML: Data) throws {
        if shouldFail { throw PasteboardError.writeFailed }
        self.snapshotXML = snapshotXML
        writeCount += 1
    }
}
