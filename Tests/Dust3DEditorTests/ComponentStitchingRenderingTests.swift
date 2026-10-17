import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class ComponentStitchingRenderingTests: XCTestCase {
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Stitching inspector did not settle")
    }
    private func save(_ data: Data, name: String) throws {
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertGreaterThan(image.pixelsWide, 0)
        XCTAssertGreaterThan(image.pixelsHigh, 0)
        let directory =
            ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("dust3d-stitching-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(name + ".png")
        try data.write(to: path, options: .atomic)
        print("Stitching inspector QA artifact: \(path.path)")
    }
    @MainActor func testActualComponentInspectorAndStitchingControlsRenderWithoutPublishingAnEdit() async throws {
        for unsupported in [false, true] {
            let original = try StitchingFixture.document(
                loop: false,
                attributes:
                    "frontClosed='true' sideClosed='true' targetSegments='12' backCloseDepthRatio='0.995' backCloseSharpness='0.005'",
                unsupported: unsupported)
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            store.selectComponent(StitchingFixture.groupID)
            try await settle(store)
            let component = try XCTUnwrap(store.snapshot?.selectedComponent)
            XCTAssertTrue(component.isGroup)
            if unsupported {
                XCTAssertNotNil(store.previewState.errorMessage)
            } else {
                XCTAssertNil(store.previewState.errorMessage)
            }
            for scheme in [ColorScheme.light, .dark] {
                let suffix = "\(unsupported ? "unsupported" : "known")-\(scheme == .dark ? "dark" : "light")"
                try save(
                    InspectorRenderer.png(
                        ComponentInspector(store: store, component: component), width: 250, scheme: scheme),
                    name: "component-inspector-" + suffix)
                try save(
                    InspectorRenderer.png(
                        ComponentStitchingControls(store: store, component: component), width: 250, scheme: scheme),
                    name: "component-stitching-" + suffix)
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testLoopFillControlsAndActualPartInspectorRenderWithoutEdits() async throws {
        for flag in ["true", "false", "future"] {
            let original = try StitchingFixture.document(loop: true, attributes: "", fillLoopInterior: flag)
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            store.selectPart(StitchingFixture.identity(101))
            try await settle(store)
            let part = try XCTUnwrap(store.snapshot?.selectedPart)
            XCTAssertEqual(part.target, .stitchingLoop)
            for scheme in [ColorScheme.light, .dark] {
                let suffix = "\(flag)-\(scheme == .dark ? "dark" : "light")"
                try save(
                    InspectorRenderer.png(PartInspector(store: store, part: part), width: 250, scheme: scheme),
                    name: "loop-part-inspector-" + suffix)
                try save(
                    InspectorRenderer.png(
                        PartLoopInteriorControls(store: store, part: part), width: 250, scheme: scheme),
                    name: "loop-interior-" + suffix)
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }

}
