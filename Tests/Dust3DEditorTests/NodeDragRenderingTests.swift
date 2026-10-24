import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class NodeDragRenderingTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Canvas fixture did not settle")
    }

    @MainActor func testCanvasRendersPreviewAndCancellationWithoutEditingArchive() async throws {
        let first = "{11111111-1111-4111-8111-111111111111}"
        let second = "{22222222-2222-4222-8222-222222222222}"
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        var source = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in [first, second].enumerated() {
            source = try source.applying(
                .addNode(
                    id: id, partID: part,
                    componentID: index == 0 ? "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}" : nil,
                    position: .init(x: 0.35 + Double(index) * 0.3, y: 0.5, z: 0.5), radius: 0.1))
        }
        source = try source.applying(.addEdge(id: "{44444444-4444-4444-8444-444444444444}", from: first, to: second))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.select(first)
        try await settle(store)
        let originalPosition = try XCTUnwrap(store.snapshot?.nodes.first { $0.id == first })
        let root =
            ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("dust3d-node-canvas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for state in ["before", "preview", "cancelled"] {
                if state == "preview" {
                    store.updateNodeDrag(
                        anchorID: first, translation: .init(x: 40, y: -30),
                        projection: .init(bounds: store.bounds, plane: .front, width: 600, height: 400),
                        generation: store.canvasDragGeneration)
                    XCTAssertTrue(store.hasNodeDrag)
                    XCTAssertNotEqual(store.nodeDragPreviewPosition(originalPosition), originalPosition.value.position)
                } else if state == "cancelled" {
                    store.cancelCanvasDrag()
                    XCTAssertFalse(store.hasNodeDrag)
                    XCTAssertEqual(store.nodeDragPreviewPosition(originalPosition), originalPosition.value.position)
                }
                let data = try InspectorRenderer.png(
                    NodeCanvas(store: store).frame(width: 600, height: 400),
                    width: 632, scheme: scheme)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                let target = root.appendingPathComponent(
                    "node-canvas-\(scheme == .dark ? "dark" : "light")-\(state).png")
                try data.write(to: target, options: .atomic)
                print("Canvas QA artifact: \(target.path)")
                XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testCanvasRendersOriginModePreviewAndCancellationWithoutEditingArchive() async throws {
        let source = Dust3DDocument.emptyArchive()
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source)
        try await settle(store)
        let root =
            ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "dust3d-origin-canvas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for state in ["enabled", "preview", "cancelled"] {
                if state == "enabled" {
                    store.setMovingOrigin(true)
                } else if state == "preview" {
                    store.updateOriginDrag(
                        translation: .init(x: 40, y: -30),
                        projection: .init(bounds: store.bounds, plane: .front, width: 600, height: 400),
                        generation: store.canvasDragGeneration)
                    XCTAssertNotNil(store.originDragPosition)
                } else {
                    store.cancelCanvasDrag()
                    XCTAssertNil(store.originDragPosition)
                    XCTAssertFalse(store.isMovingOrigin)
                }
                let data = try InspectorRenderer.png(
                    NodeCanvas(store: store).frame(width: 600, height: 400),
                    width: 632, scheme: scheme)
                let target = root.appendingPathComponent(
                    "origin-canvas-\(scheme == .dark ? "dark" : "light")-\(state).png")
                try data.write(to: target, options: .atomic)
                print("Origin QA artifact: \(target.path)")
                XCTAssertEqual(store.snapshot?.document.encoded(), source)
                XCTAssertFalse(store.canUndo)
            }
        }
    }

}
