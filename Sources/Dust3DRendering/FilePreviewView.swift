import SwiftUI

/// Read-only system preview content; owns camera controls without document editing or save actions.
public struct FilePreviewView: View {
    private let document: FilePreviewDocument
    @State private var isWireframe = false
    @State private var viewportFocus = MeshViewportFocus()
    @State private var cameraReset = 0
    @State private var cameraCommand: MeshCameraCommand?
    @State private var renderIssue: String?
    @State private var materialsRendered = false
    @State private var materialRenderIssue: String?

    /// Display one immutable prepared document in a Quick Look host.
    /// - Parameter document: Geometry/maps from a single read-only archive snapshot.
    public init(document: FilePreviewDocument) { self.document = document }

    public var body: some View {
        VStack(spacing: 0) {
            if let issue = renderIssue {
                ContentUnavailableView {
                    Label("Preview unavailable", systemImage: "cube.transparent")
                } description: {
                    Text(issue)
                }
            } else if let mesh = document.mesh {
                MeshViewport(
                    mesh: mesh, isWireframe: isWireframe, cameraReset: cameraReset,
                    materials: materialRenderIssue == nil ? document.materials : nil, cameraCommand: cameraCommand,
                    onMaterialError: {
                        materialRenderIssue = $0
                        materialsRendered = false
                    },
                    onMaterialRendered: { materialsRendered = true }, onError: { renderIssue = $0 }
                )
                .withFocusTarget(viewportFocus)
                .accessibilityLabel("Read-only 3D object preview")
            } else {
                ContentUnavailableView {
                    Label("No visible mesh", systemImage: "cube.transparent")
                } description: {
                    Text("This document has no enabled procedural geometry.")
                }
            }
            if let issue = materialRenderIssue ?? document.materialError?.localizedDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Showing geometry without materials", systemImage: "exclamationmark.triangle")
                    Text(issue).textSelection(.enabled)
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            if let warning = document.compatibilityWarning(
                materialsRendered: materialsRendered, materialRenderingFailed: materialRenderIssue != nil)
            {
                Text(warning).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(8)
            }
            if let issue = document.materialSourceCapabilities.issue {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Material source details unavailable", systemImage: "info.circle")
                    Text(issue.localizedDescription).textSelection(.enabled)
                }.font(.caption).foregroundStyle(.secondary).padding(8)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack {
                    cameraControls
                    meshSummary
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) {
                    cameraControls
                    meshSummary
                }
            }
            .disabled(document.mesh == nil || renderIssue != nil)
            .padding(10)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cameraControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                wireframeControl
                cameraButtons
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                wireframeControl
                cameraButtons
            }
        }
    }

    private var wireframeControl: some View {
        Toggle("Wireframe", isOn: $isWireframe).toggleStyle(.checkbox)
    }

    private var cameraButtons: some View {
        HStack {
            Button {
                viewportFocus.moveFocusInHostWindow()
            } label: {
                Label("Focus Object", systemImage: "viewfinder").labelStyle(.iconOnly)
            }
            .accessibilityLabel("Focus Object")
            .help("Focus the preview to orbit with the arrow keys")
            Button {
                cameraCommand = MeshCameraCommand(.zoomOut)
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass").labelStyle(.iconOnly)
            }
            .accessibilityLabel("Zoom Out")
            .help("Zoom Out")
            Button {
                cameraCommand = MeshCameraCommand(.zoomIn)
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass").labelStyle(.iconOnly)
            }
            .accessibilityLabel("Zoom In")
            .help("Zoom In")
            Button {
                cameraCommand = nil
                cameraReset += 1
            } label: {
                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right").labelStyle(.iconOnly)
            }
            .accessibilityLabel("Fit Object")
            .help("Reset the camera and fit the object")
        }
    }

    @ViewBuilder private var meshSummary: some View {
        if let mesh = document.mesh {
            Text("\(mesh.triangleCount) triangles · Drag or use arrow keys to orbit")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
