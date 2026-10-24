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

    @MainActor func testNativeFieldSubmitsAndRefreshesByteDistinctUnicodeLookupNames() async throws {
        _ = NSApplication.shared
        let composed = "Caf\u{e9}"
        let decomposed = "Cafe\u{301}"
        let source = try document().applying(.setEdgeBoneName(id: edgeID, name: composed))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: source.encoded())
        try await settle(store)
        store.selectEdge(edgeID)
        try await settle(store)
        let edge = try XCTUnwrap(store.snapshot?.selectedEdge)
        let host = NSHostingView(rootView: EdgeBoneBindingControls(store: store, edge: edge))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 320),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0..<100 where editableField(in: host) == nil {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let field = try XCTUnwrap(editableField(in: host))
        for _ in 0..<100 where !field.stringValue.utf8.elementsEqual(composed.utf8) {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(field.stringValue.utf8.elementsEqual(composed.utf8))
        window.makeKey()
        field.selectText(nil)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        let selection = NSRange(location: 1, length: 2)
        editor.setSelectedRange(selection)
        host.rootView = EdgeBoneBindingControls(store: store, edge: edge)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertEqual(editor.selectedRange(), selection, "Unrelated publications must retain native selection")
        editor.insertText("DraftOnly", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        let cancel = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53))
        window.sendEvent(cancel)
        for _ in 0..<100 where !editor.string.utf8.elementsEqual(composed.utf8) {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(editor.string.utf8.elementsEqual(composed.utf8))
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        editor.insertText(decomposed, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertTrue(editor.string.utf8.elementsEqual(decomposed.utf8))
        let submit = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36))
        window.sendEvent(submit)
        try await settle(store)
        XCTAssertTrue(try XCTUnwrap(store.snapshot?.selectedEdge).hasExactBoneName(decomposed))
        host.rootView = EdgeBoneBindingControls(store: store, edge: try XCTUnwrap(store.snapshot?.selectedEdge))
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertTrue(field.stringValue.utf8.elementsEqual(decomposed.utf8))
        store.setEdgeBoneName(edgeID, name: composed)
        try await settle(store)
        host.rootView = EdgeBoneBindingControls(store: store, edge: try XCTUnwrap(store.snapshot?.selectedEdge))
        for _ in 0..<100 where !field.stringValue.utf8.elementsEqual(composed.utf8) {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(
            field.stringValue.utf8.elementsEqual(composed.utf8), "Accepted byte-distinct snapshots must reset the draft"
        )
    }

    @MainActor private func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { self.editableField(in: $0) }.first
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
