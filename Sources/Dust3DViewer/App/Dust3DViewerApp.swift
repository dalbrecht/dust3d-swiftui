import AppKit
import SwiftUI

@main
struct Dust3DViewerApp: App {
    @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) private var appDelegate
    @FocusedValue(\.openDocument) private var openDocument

    var body: some Scene {
        WindowGroup("Dust3D Viewer") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    openDocument?()
                }
                .keyboardShortcut("o")
                .disabled(openDocument == nil)
            }
        }
    }
}

@MainActor
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
