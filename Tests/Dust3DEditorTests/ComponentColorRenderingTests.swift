import AppKit
import Dust3DDocument
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class ComponentColorRenderingTests: XCTestCase {
    private let id = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
    private func document(_ color: String?) throws -> Dust3DDocument {
        let attributes = color.map { "color='\($0)'" } ?? ""
        let model = Data(
            "<canvas><nodes/><edges/><parts/><components><component id='\(id)' future='preserve' \(attributes)/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }

    @MainActor func testColorDraftsRenderAbsentOpaqueAlphaAndUnsupportedStatesWithoutPublishing() async throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("component-color", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, value): (String, String?) in [
            ("unset", nil), ("opaque", "#3366CC"), ("alpha", "#803366CC"), ("unsupported", "future"), ("empty", ""),
            ("long", String(repeating: "future", count: 40)),
        ] {
            let source = try document(value)
            let store = EditorStore()
            defer { store.stop() }
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            await store.load(data: source.encoded())
            store.selectComponent(id)
            for _ in 0..<300 {
                if !store.isWorking && !store.isGenerating { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let component = try XCTUnwrap(store.snapshot?.selectedComponent)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    ComponentColorControls(store: store, component: component), width: 250, scheme: scheme)
                let image = try XCTUnwrap(NSBitmapImageRep(data: data))
                XCTAssertGreaterThan(image.pixelsWide, 0)
                let path = directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: path, options: .atomic)
                print("Component color QA artifact: \(path.path)")
                XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
                XCTAssertEqual(publications, 0)
                XCTAssertFalse(store.canUndo)
            }
        }
    }
}
