import AppKit
import Dust3DDocument
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class ComponentWrappingRenderingTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<3000 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Wrapping inspector did not settle within 30 seconds")
    }
    private func save(_ data: Data, name: String) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        let directory =
            ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("dust3d-wrapping-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(name + ".png")
        try data.write(to: path, options: .atomic)
        print("Wrapping inspector QA artifact: \(path.path)")
    }
    @MainActor func testActualInspectorAndWrappingControlsRenderAllSourceModesWithoutEdits() async throws {
        let cases = [
            ("none", "", "wrapFaces='64'"), ("skin", "Skin", "wrapFaces='64'"), ("cloth", "Cloth", "wrapFaces='64'"),
            ("unsupported-mode", "Future", "wrapFaces='64'"),
            ("unsupported-values", "Cloth", "wrapFaces='future' wrapKeep='future' wrapOffset='future'"),
        ]
        for (name, mode, attributes) in cases {
            let source = try WrappingFixture.document(mode: mode, attributes: attributes)
            let store = EditorStore()
            defer { store.stop() }
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            await store.load(data: source.encoded())
            try await settle(store)
            store.selectComponent(WrappingFixture.groupID)
            try await settle(store)
            let component = try XCTUnwrap(store.snapshot?.selectedComponent)
            XCTAssertTrue(component.isGroup)
            for scheme in [ColorScheme.light, .dark] {
                let suffix = name + (scheme == .dark ? "-dark" : "-light")
                try save(
                    InspectorRenderer.png(
                        ComponentWrappingControls(store: store, component: component), width: 250, scheme: scheme),
                    name: "wrapping-" + suffix)
                try save(
                    InspectorRenderer.png(
                        ComponentInspector(store: store, component: component), width: 250, scheme: scheme),
                    name: "component-wrapping-" + suffix)
                XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
                XCTAssertFalse(store.canUndo)
                XCTAssertEqual(publications, 0)
            }
        }
    }
}
