import AppKit
import Dust3DRendering
import SwiftUI

@main
struct Dust3DViewerApp: App {
    @Environment(\.openWindow) private var openWindow
    private let buildIdentity = RuntimeBuildIdentity.current
    @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) private var appDelegate
    @FocusedValue(\.openDocument) private var openDocument
    @FocusedValue(\.viewerPreviewFocus) private var previewFocus

    private var applicationName: String {
        BuildIdentityPresentation.applicationName(
            bundleIdentifier: buildIdentity.launchBundleIdentifier, fallback: "Dust3D Viewer")
    }

    var body: some Scene {
        WindowGroup("Dust3D Viewer") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandMenu("View") {
                Button("Focus 3D Preview") { previewFocus?.moveFocus(in: NSApp.keyWindow) }
                    .disabled(previewFocus == nil)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About \(applicationName)") {
                    ApplicationAboutPanel.show(applicationName: applicationName)
                }
            }
            CommandGroup(after: .help) {
                Button("Build Diagnostics") { openWindow(id: "build-diagnostics") }
                Divider()
                ForEach(ApplicationHelpLink.allCases, id: \.self) { link in
                    Button(link.title) { link.open() }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    openDocument?()
                }
                .keyboardShortcut("o")
                .disabled(openDocument == nil)
            }
        }
        Window("Build Diagnostics – \(applicationName)", id: "build-diagnostics") {
            BuildDiagnosticsView(applicationName: applicationName, identity: buildIdentity)
        }
        .defaultSize(width: 660, height: 520)
    }
}

@MainActor
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let buildIdentity = RuntimeBuildIdentity.current

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildIdentity.logStartup(fallbackSubsystem: "org.dust3d.viewer")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

}

private struct OpenDocumentKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ViewerPreviewFocusKey: FocusedValueKey {
    typealias Value = MeshViewportFocus
}

extension FocusedValues {
    var viewerPreviewFocus: MeshViewportFocus? {
        get { self[ViewerPreviewFocusKey.self] }
        set { self[ViewerPreviewFocusKey.self] = newValue }
    }

    var openDocument: (() -> Void)? {
        get { self[OpenDocumentKey.self] }
        set { self[OpenDocumentKey.self] = newValue }
    }
}
