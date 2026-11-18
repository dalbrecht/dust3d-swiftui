import AppKit
import Dust3DRendering
import SwiftUI

@main
struct Dust3DViewerApp: App {
    @Environment(\.openWindow) private var openWindow
    private let buildIdentity = RuntimeBuildIdentity.current
    @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) private var appDelegate
    @FocusedValue(\.viewerCancellation) private var cancelOperation
    @FocusedValue(\.viewerPreviewRetryStore) private var retryStore
    @FocusedValue(\.openDocument) private var openDocument

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
                let window = NSApp.keyWindow
                let ownsPreviewWindow: @MainActor () -> Bool = { [weak window] in
                    guard let window, NSApp.keyWindow === window else { return false }
                    return window.attachedSheet == nil && window.sheetParent == nil && NSApp.modalWindow == nil
                }
                let retryPreview = retryStore?.rendererRetryAction(ownsWindow: ownsPreviewWindow)
                Button("Retry Preview") { retryPreview?() }
                    .disabled(retryPreview == nil)
                let retryMaterials = retryStore?.materialRetryAction(ownsWindow: ownsPreviewWindow)
                Button("Retry Materials") { retryMaterials?() }
                    .disabled(retryMaterials == nil)
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
                Button("Cancel Current Operation") { cancelOperation?() }
                    .disabled(cancelOperation == nil)
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

private struct ViewerCancellationKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ViewerPreviewRetryStoreKey: FocusedValueKey {
    typealias Value = ViewerStore
}

extension FocusedValues {
    var viewerPreviewRetryStore: ViewerStore? {
        get { self[ViewerPreviewRetryStoreKey.self] }
        set { self[ViewerPreviewRetryStoreKey.self] = newValue }
    }

    var viewerCancellation: (() -> Void)? {
        get { self[ViewerCancellationKey.self] }
        set { self[ViewerCancellationKey.self] = newValue }
    }

    var openDocument: (() -> Void)? {
        get { self[OpenDocumentKey.self] }
        set { self[OpenDocumentKey.self] = newValue }
    }
}
