import AppKit
import Dust3DDocument
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor private enum InspectorRenderer {
    enum Failure: Error, Equatable { case invalidSize, bitmapUnavailable, encodingUnavailable, visibleWindow }

    static func png<Content: View>(_ content: Content, width: CGFloat, scheme: ColorScheme) throws -> Data {
        guard width.isFinite, width > 0, width <= 1000 else { throw Failure.invalidSize }
        // This artifact-exporting test process must never appear in the Dock or activate a product app.
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 1000),
            styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.appearance = appearance
        let root = content.padding(16).frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme).environment(\.displayScale, 2)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // SwiftUI initial state updates must settle before measuring the full scroll-content height.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        hosting.layoutSubtreeIfNeeded()
        let height = ceil(hosting.fittingSize.height)
        guard height.isFinite, height > 0, height <= 4096 else { throw Failure.invalidSize }
        window.setContentSize(NSSize(width: width, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        guard !window.isVisible else { throw Failure.visibleWindow }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw Failure.bitmapUnavailable
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.encodingUnavailable }
        return data
    }
}

final class PartModifierRenderingTests: XCTestCase {
    private let partID = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private func document(unsupported: Bool) throws -> Dust3DDocument {
        let flags = PartModifierProperty.allCases.map { property in
            let enabled = property == .subdivision || property == .roundedEnds || property == .hardJoin
            return "\(property.rawValue)='\(unsupported ? "future" : enabled ? "true" : "false")'"
        }.joined(separator: " ")
        let name = unsupported ? "QA Unsupported Flags" : "QA Known Flags"
        let model = Data(
            "<canvas originX='.5' originY='.5' originZ='.5'><nodes><node id='{11111111-1111-4111-8111-111111111111}' partId='\(partID)' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='\(partID)' name='\(name)' future='preserved' deformWidth='\(unsupported ? "future" : "0.995")' deformThickness='\(unsupported ? "future" : "1.25")' deformUnified='\(unsupported ? "future" : "true")' \(flags)/></parts><components><component id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId' linkData='\(partID)' color='#3366cc'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Inspector fixture did not settle")
    }
    private func outputDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(
            "dust3d-editor-ui-qa-\(UUID().uuidString)", isDirectory: true)
    }
    private func save(_ data: Data, name: String, directory: URL) throws {
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertGreaterThan(image.pixelsWide, 0)
        XCTAssertGreaterThan(image.pixelsHigh, 0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".png")
        try data.write(to: url, options: .atomic)
        print("Inspector QA artifact: \(url.path)")
    }
    @MainActor func testActualInspectorRendersKnownAndUnsupportedStatesWithoutEditingDocument() async throws {
        let directory = outputDirectory()
        for unsupported in [false, true] {
            let original = try document(unsupported: unsupported)
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            store.selectPart(partID)
            try await settle(store)
            if unsupported {
                XCTAssertNotNil(store.previewState.errorMessage)
            } else {
                XCTAssertNil(store.previewState.errorMessage)
            }
            let part = try XCTUnwrap(store.snapshot?.selectedPart)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    PartInspector(store: store, part: part), width: 250, scheme: scheme)
                try save(
                    data,
                    name:
                        "part-inspector-\(unsupported ? "unsupported" : "known")-\(scheme == .dark ? "dark" : "light")",
                    directory: directory)
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testModifierSectionRendersWithoutPublishingAnEdit() async throws {
        let original = try document(unsupported: false)
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let part = try XCTUnwrap(store.snapshot?.parts.first)
        let data = try InspectorRenderer.png(PartModifierControls(store: store, part: part), width: 250, scheme: .light)
        try save(data, name: "part-modifier-section", directory: outputDirectory())
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(store.canUndo)
    }
    @MainActor func testDeformationControlsRenderWithoutChangingSourceOrHistory() async throws {
        for unsupported in [false, true] {
            let original = try document(unsupported: unsupported)
            let store = EditorStore()
            defer { store.stop() }
            await store.load(data: original.encoded())
            try await settle(store)
            let part = try XCTUnwrap(store.snapshot?.parts.first)
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    PartDeformationControls(store: store, part: part), width: 250, scheme: scheme)
                try save(
                    data,
                    name:
                        "part-deformation-\(unsupported ? "unsupported" : "known")-\(scheme == .dark ? "dark" : "light")",
                    directory: outputDirectory())
                XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
                XCTAssertFalse(store.canUndo)
            }
        }
    }
    @MainActor func testInvalidRenderWidthsRejectBeforeWindowCreation() {
        for width in [CGFloat.zero, -1, .infinity, 1001] {
            XCTAssertThrowsError(try InspectorRenderer.png(Text("No window"), width: width, scheme: .light)) {
                XCTAssertEqual($0 as? InspectorRenderer.Failure, .invalidSize)
            }
        }
    }
}
