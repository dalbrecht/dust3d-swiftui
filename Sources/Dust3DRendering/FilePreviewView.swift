import SwiftUI

/// Read-only system preview content; owns camera controls without document editing or save actions.
public struct FilePreviewView: View {
    private let document: FilePreviewDocument
    @State private var isWireframe = false
    @State private var cameraReset = 0
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
                    bakedMesh: materialRenderIssue == nil ? document.bakedMesh : nil,
                    onMaterialError: {
                        materialRenderIssue = $0
                        materialsRendered = false
                    },
                    onMaterialRendered: { materialsRendered = true }, onError: { renderIssue = $0 }
                )
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
        HStack {
            Toggle("Wireframe", isOn: $isWireframe).toggleStyle(.checkbox)
            Button {
                cameraReset += 1
            } label: {
                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }.help("Reset the camera and fit the object")
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var meshSummary: some View {
        if let mesh = document.mesh {
            Text("\(mesh.triangleCount) triangles · Drag to orbit · Scroll to zoom")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
