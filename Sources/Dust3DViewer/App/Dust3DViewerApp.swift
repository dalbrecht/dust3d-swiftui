import AppKit
import Dust3DRendering
import SwiftUI

@main
struct Dust3DViewerApp: App {
    @Environment(\.openWindow) private var openWindow
    private let buildIdentity = RuntimeBuildIdentity.current
    @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) private var appDelegate
    @FocusedValue(\.openDocument) private var openDocument
    @FocusedValue(\.viewerStore) private var store

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
                Toggle("Wireframe", isOn: store?.wireframeBinding ?? .constant(false))
                    .keyboardShortcut("w", modifiers: [])
                    .disabled(store?.mesh == nil)
                Toggle("Automatic Rotation", isOn: store?.automaticRotationBinding ?? .constant(false))
                    .keyboardShortcut("r", modifiers: [])
                    .disabled(store?.mesh == nil)
                Divider()
                Button("Fit Model") { store?.fitModel() }
                    .keyboardShortcut("0")
                    .disabled(store?.mesh == nil)
                cameraItem("Zoom In", .zoomIn).keyboardShortcut("=")
                cameraItem("Zoom Out", .zoomOut).keyboardShortcut("-")
                Menu("Orbit") {
                    cameraItem("Orbit Left", .orbitLeft)
                    cameraItem("Orbit Right", .orbitRight)
                    cameraItem("Orbit Up", .orbitUp)
                    cameraItem("Orbit Down", .orbitDown)
                }
                Menu("Pan") {
                    cameraItem("Pan Left", .panLeft)
                    cameraItem("Pan Right", .panRight)
                    cameraItem("Pan Up", .panUp)
                    cameraItem("Pan Down", .panDown)
                }
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

    private func cameraItem(_ title: LocalizedStringKey, _ action: MeshCameraCommand.Action) -> some View {
        Button(title) { store?.moveCamera(action) }
            .disabled(store?.mesh == nil)
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

extension ViewerStore {
    var wireframeBinding: Binding<Bool> {
        Binding(get: { self.isWireframe }, set: { self.setWireframe($0) })
    }

    var automaticRotationBinding: Binding<Bool> {
        Binding(get: { self.automaticallyRotates }, set: { self.setAutomaticallyRotates($0) })
    }
}

private struct ViewerStoreKey: FocusedValueKey {
    typealias Value = ViewerStore
}

private struct OpenDocumentKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var viewerStore: ViewerStore? {
        get { self[ViewerStoreKey.self] }
        set { self[ViewerStoreKey.self] = newValue }
    }

    var openDocument: (() -> Void)? {
        get { self[OpenDocumentKey.self] }
        set { self[OpenDocumentKey.self] = newValue }
    }
}
