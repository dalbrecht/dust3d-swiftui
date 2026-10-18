import AppKit
import Dust3DRendering
import SwiftUI

@main
struct Dust3DViewerApp: App {
    @Environment(\.openWindow) private var openWindow
    private let buildIdentity = RuntimeBuildIdentity.current
    @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) private var appDelegate
    @FocusedValue(\.openDocument) private var openDocument

    var body: some Scene {
        WindowGroup("Dust3D Viewer") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Dust3D Viewer…") { openWindow(id: "build-diagnostics") }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    openDocument?()
                }
                .keyboardShortcut("o")
                .disabled(openDocument == nil)
            }
        }
        Window("About Dust3D Viewer", id: "build-diagnostics") {
            BuildDiagnosticsView(applicationName: "Dust3D Viewer", identity: buildIdentity)
        }
        .defaultSize(width: 660, height: 520)
    }
}

@MainActor
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let buildIdentity = RuntimeBuildIdentity.current

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildIdentity.logStartup(subsystem: Bundle.main.bundleIdentifier ?? "org.dust3d.viewer")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

}

private struct OpenDocumentKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openDocument: (() -> Void)? {
        get { self[OpenDocumentKey.self] }
        set { self[OpenDocumentKey.self] = newValue }
    }
}
