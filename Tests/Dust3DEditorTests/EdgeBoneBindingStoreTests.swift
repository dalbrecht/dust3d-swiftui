import AppKit
import Dust3DDocument
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class EdgeBoneBindingStoreTests: XCTestCase {
    private let edgeID = "{44444444-4444-4444-8444-444444444444}"
    private func document() throws -> Dust3DDocument {
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let nodes = ["{11111111-1111-4111-8111-111111111111}", "{22222222-2222-4222-8222-222222222222}"]
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in nodes.enumerated() {
            document = try document.applying(
                .addNode(
                    id: id, partID: part, componentID: index == 0 ? "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}" : nil,
                    position: .init(x: 0.5, y: 0.5, z: Double(index)), radius: 0.1))
        }
        return try document.applying(.addEdge(id: edgeID, from: nodes[0], to: nodes[1]))
    }

    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Bone binding or ordinary preview did not settle")
    }

    @MainActor func testBindingApplyClearAndRejectRetainGeometrySelectionCameraAndExactHistory() async throws {
        let original = try document()
        let preview = CountingBoneBindingPreview()
        let store = EditorStore(preview: preview)
        defer { store.stop() }
        var publications = 0
        store.onDocumentChanged = { _ in publications += 1 }
        await store.load(data: original.encoded())
        try await settle(store)
        store.selectEdge(edgeID)
        try await settle(store)
        let camera = store.cameraReset
        let previewRevision = store.previewRevision
        let materialRevision = store.materialViewportRevision
        let positions = try XCTUnwrap(store.mesh).vertices.map(\.position)
        store.setEdgeBoneName(edgeID, name: "Root")
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.selectedEdge?.boneName, "Root")
        XCTAssertEqual(store.snapshot?.selectedEdgeID, edgeID)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), positions)
        XCTAssertEqual(publications, 1)
        let bound = try XCTUnwrap(store.snapshot?.document.encoded())
        store.setEdgeBoneName(edgeID, name: "Root")
        try await settle(store)
        XCTAssertEqual(publications, 1)
        store.setEdgeBoneName(edgeID, name: "bad\nname")
        try await settle(store)
        XCTAssertEqual(store.errorMessage, EditorStore.message(DocumentError.invalidBoneName))
        XCTAssertEqual(store.snapshot?.document.encoded(), bound)
        store.setEdgeBoneName(edgeID, name: "")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedEdge?.boneName, "")
        let requests = await preview.requests
        XCTAssertEqual(requests, 1, "Stored bindings must not enqueue geometry or rig evaluation")
        XCTAssertEqual(store.previewRevision, previewRevision)
        XCTAssertEqual(store.materialViewportRevision, materialRevision)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), bound)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), bound)
        store.stop()
        store.setEdgeBoneName(edgeID, name: "After stop")
        XCTAssertEqual(store.snapshot?.document.encoded(), bound)
    }

    @MainActor func testInspectorRendersUnassignedBoundAndReadonlyWithoutPublishingEdits() async throws {
        let base = try document()
        let bound = try base.applying(.setEdgeBoneName(id: edgeID, name: "Root"))
        let readonly = try bound.applying(
            .setPartState(id: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", property: .locked, value: true))
        let root =
            ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("ui-qa/edge-bone", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, source) in [("unassigned", base), ("bound", bound), ("readonly", readonly)] {
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: source.encoded())
            try await settle(store)
            store.selectEdge(edgeID)
            try await settle(store)
            let edge = try XCTUnwrap(store.snapshot?.selectedEdge)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    EdgeInspector(store: store, edge: edge), width: 250, scheme: scheme)
                let image = try XCTUnwrap(NSBitmapImageRep(data: data))
                XCTAssertGreaterThan(image.pixelsHigh, 0)
                let destination = directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: destination, options: .atomic)
                print("Bone inspector QA artifact: \(destination.path)")
                XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
}

private actor CountingBoneBindingPreview: EditorPreviewServing {
    private let service = EditorPreviewService()
    private(set) var requests = 0
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        requests += 1
        return try await service.generate(data, scopeID: scopeID)
    }
    func reset(scopeID: UUID) async throws { try await service.reset(scopeID: scopeID) }
}
