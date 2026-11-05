import AppKit
import Dust3DDocument
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class EdgeMidpointStoreTests: XCTestCase {
    func testAvailabilityAndAsyncHistoryFollowSelectedEdgeEditability() async throws {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        document = try document.applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        document = try document.applying(
            .addNode(
                id: "{22222222-2222-4222-8222-222222222222}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: nil, position: .init(x: 1, y: 0, z: 0), radius: 0.3))
        document = try document.applying(
            .addEdge(
                id: "{44444444-4444-4444-8444-444444444444}", from: "{11111111-1111-4111-8111-111111111111}",
                to: "{22222222-2222-4222-8222-222222222222}"))
        let store = EditorStore()
        defer { store.stop() }
        XCTAssertFalse(store.canInsertEdgeMidpoint)
        await store.load(data: document.encoded())
        try await settle(store)
        XCTAssertFalse(store.canInsertEdgeMidpoint)
        store.selectEdge("{44444444-4444-4444-8444-444444444444}")
        try await settle(store)
        XCTAssertTrue(store.canInsertEdgeMidpoint)
        let otherWindow = EditorStore()
        defer { otherWindow.stop() }
        await otherWindow.load(data: document.encoded())
        try await settle(otherWindow)
        try render(store, name: "editable")
        let previewRevision = store.previewRevision
        store.insertSelectedEdgeMidpoint()
        XCTAssertFalse(store.canInsertEdgeMidpoint, "Both native command surfaces disable during the transaction")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdgeID, "{44444444-4444-4444-8444-444444444444}")
        XCTAssertEqual(store.snapshot?.nodes.count, 3)
        XCTAssertNotNil(store.mesh, "Pinned core preview must regenerate midpoint geometry")
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertGreaterThan(store.previewRevision, previewRevision)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(otherWindow.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(otherWindow.canUndo)
        try render(store, name: "inserted")
        XCTAssertTrue(store.canInsertEdgeMidpoint)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 3)
        let locked = try document.applying(
            .setPartState(id: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", property: .locked, value: true))
        await store.load(data: locked.encoded())
        try await settle(store)
        store.selectEdge("{44444444-4444-4444-8444-444444444444}")
        try await settle(store)
        XCTAssertFalse(store.canInsertEdgeMidpoint)
        try render(store, name: "locked")
        store.insertSelectedEdgeMidpoint()
        XCTAssertEqual(store.snapshot?.document.encoded(), locked.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func render(_ store: EditorStore, name: String) throws {
        let edge = try XCTUnwrap(store.snapshot?.selectedEdge)
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("ui-qa/edge-midpoint")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let data = try InspectorRenderer.png(EdgeInspector(store: store, edge: edge), width: 300, scheme: scheme)
            try data.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Midpoint operation did not settle")
    }
}
