import AppKit
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor private final class EditorInspectorRenderingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class EditorInspectorLayoutRenderingTests: XCTestCase {
    func testStandaloneEmptyInspectorAppearanceCalibration() throws {
        let pasteboard = NSPasteboard(name: .init("org.dust3d.tests.inspector.calibration." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        for scheme in [ColorScheme.light, .dark] {
            let png = try InspectorRenderer.png(
                NodeInspector(store: EditorStore()).environment(EditorPasteboard(pasteboard: pasteboard)).frame(
                    height: 700),
                width: 250, scheme: scheme)
            if let path = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                try png.write(
                    to: URL(fileURLWithPath: path, isDirectory: true)
                        .appendingPathComponent("standalone-inspector-" + (scheme == .dark ? "dark" : "light") + ".png")
                )
            }
        }
    }

    func testEmptyProductionEditorRendersNativeInspectorWithoutOpeningAProductApp() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let originalAppearance = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = originalAppearance }
        for scheme in [ColorScheme.light, .dark] {
            let pasteboard = NSPasteboard(name: .init("org.dust3d.tests.inspector." + UUID().uuidString))
            let changeCount = pasteboard.changeCount
            defer { pasteboard.releaseGlobally() }
            let window = EditorInspectorRenderingWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 1400, height: 800),
                styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            defer {
                window.contentView = nil
                window.close()
            }
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            NSApplication.shared.appearance = appearance
            window.appearance = appearance
            // The production empty-document path skips native generation. No document file is opened.
            let root = EditorRootView(file: .constant(EditorFileDocument()))
                .environment(EditorPasteboard(pasteboard: pasteboard))
                .frame(width: 1400, height: 800)
                .environment(\.colorScheme, scheme)
                .preferredColorScheme(scheme)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: root)
            host.appearance = appearance
            host.frame = NSRect(x: 0, y: 0, width: 1400, height: 800)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(pasteboard.changeCount, changeCount)
            XCTAssertFalse(window.isVisible)
            XCTAssertLessThan(window.frame.maxX, -8000)
            XCTAssertFalse(window.isMainWindow)
            XCTAssertFalse(window.isKeyWindow)
            XCTAssertFalse(NSApplication.shared.isActive)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            appearance?.performAsCurrentDrawingAppearance {
                host.cacheDisplay(in: host.bounds, to: bitmap)
            }
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 100)
            if let path = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                let destination = URL(fileURLWithPath: path, isDirectory: true)
                    .appendingPathComponent("editor-inspector-" + (scheme == .dark ? "dark" : "light") + ".png")
                try png.write(to: destination, options: .atomic)
            }
        }
    }
}
