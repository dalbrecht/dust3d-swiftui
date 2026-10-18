import AppKit
import Dust3DDocument
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class ComponentColorImageRenderingTests: XCTestCase {
    private let component = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
    private func document(_ image: String?) throws -> Dust3DDocument {
        let attribute = image.map { "colorImageId='\($0)'" } ?? ""
        let model = Data(
            "<canvas><nodes/><edges/><parts/><components><component id='\(component)' \(attribute)/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }

    @MainActor func testImageControlsRenderSourceAndRetainedStatesWithoutMutatingArchive() async throws {
        let directory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] ?? NSTemporaryDirectory()
        )
        .appendingPathComponent("component-color-image", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
            ))
        for (name, raw): (String, String?) in [
            ("unset", nil), ("empty", ""), ("unsupported", "future"), ("long", String(repeating: "future", count: 80)),
            ("missing", "dddddddd-dddd-4ddd-8ddd-dddddddddddd"), ("retained", nil),
        ] {
            var source = try document(raw)
            if name == "retained" {
                source = try source.applying(
                    .importComponentColorImage(id: component, imageID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd", png: png)
                )
            }
            let store = EditorStore()
            defer { store.stop() }
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            await store.load(data: source.encoded())
            for _ in 0..<300 {
                if !store.isWorking { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            store.selectComponent(component)
            for _ in 0..<300 {
                if !store.isWorking { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let selected = try XCTUnwrap(store.snapshot?.selectedComponent)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    ComponentColorImageControls(store: store, component: selected), width: 250, scheme: scheme)
                let image = try XCTUnwrap(NSBitmapImageRep(data: data))
                XCTAssertGreaterThan(image.pixelsWide, 0)
                try data.write(
                    to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
                XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
                XCTAssertEqual(publications, 0)
                XCTAssertFalse(store.canUndo)
            }
        }
    }
}
