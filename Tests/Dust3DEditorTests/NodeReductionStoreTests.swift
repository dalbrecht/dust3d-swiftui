import AppKit
import Dust3DDocument
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class NodeReductionStoreTests: XCTestCase {
    private let ids = (1...4).map { "{00000000-0000-4000-8000-00000000000\($0)}" }
    private let partID = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"

    private func chain() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ids.enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: partID,
                    componentID: index == 0 ? "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        for index in 0..<3 {
            document = try document.applying(
                .addEdge(
                    id: "{11111111-1111-4111-8111-11111111111\(index)}",
                    from: ids[index], to: ids[index + 1]))
        }
        return document
    }

    func testBatchRoutingAvailabilityHistoryAndFreshPreview() async throws {
        let document = try chain()
        let store = EditorStore()
        let otherWindow = EditorStore()
        defer {
            store.stop()
            otherWindow.stop()
        }
        XCTAssertFalse(store.canReduceSelectedNodes)
        await store.load(data: document.encoded())
        await otherWindow.load(data: document.encoded())
        try await settle(store)
        try await settle(otherWindow)
        store.select(Set(ids.prefix(3)))
        try await settle(store)
        XCTAssertTrue(store.canReduceSelectedNodes)
        try render(store, name: "eligible-batch")
        let revision = store.previewRevision
        store.reduceSelectedNodes()
        XCTAssertFalse(store.canReduceSelectedNodes)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedIDs, [ids[0]])
        XCTAssertEqual(store.snapshot?.nodes.count, 2)
        XCTAssertFalse(store.canReduceSelectedNodes)
        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(store.mesh)
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertGreaterThan(store.previewRevision, revision)
        XCTAssertEqual(otherWindow.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(otherWindow.canUndo)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), document.encoded())
        XCTAssertFalse(store.canUndo)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.nodes.count, 2)
        let locked = try document.applying(.setPartState(id: partID, property: .locked, value: true))
        await store.load(data: locked.encoded())
        try await settle(store)
        store.select(Set(ids.prefix(3)))
        try await settle(store)
        XCTAssertFalse(store.canReduceSelectedNodes)
        try render(store, name: "locked-batch")
        store.reduceSelectedNodes()
        XCTAssertEqual(store.snapshot?.document.encoded(), locked.encoded())
        XCTAssertFalse(store.canUndo)
    }

    private func render(_ store: EditorStore, name: String) throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("ui-qa/node-reduction")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let data = try InspectorRenderer.png(NodeReductionControls(store: store), width: 300, scheme: scheme)
            try data.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
    }

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Reduction operation did not settle")
    }
}
