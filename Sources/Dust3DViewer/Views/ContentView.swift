import Dust3DKit
import Dust3DRendering
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var store = ViewerStore()
    @State private var isImporterPresented = false
    @State private var isWireframe = false
    var body: some View {
        let cancelOperation = isImporterPresented ? nil : store.pendingCancellation
        let rendererAttempt = store.rendererAttemptID
        VStack(spacing: 0) {
            if let message = store.errorMessage ?? store.rendererError {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message).textSelection(.enabled)
                    Spacer()
                    if store.errorMessage != nil {
                        Button("Dismiss") { store.errorMessage = nil }
                    } else {
                        if let retryPreview = store.rendererRetryAction {
                            Button("Retry Preview", action: retryPreview)
                        }
                        Button("Dismiss") { store.dismissRendererError(attemptID: rendererAttempt) }
                    }
                }
                .padding()
                Divider()
            }
            ZStack {
                if let mesh = store.mesh {
                    let materialRevision = store.meshRevision + store.materialRevision
                    MeshViewport(
                        mesh: mesh, isWireframe: isWireframe, cameraReset: 0,
                        meshRevision: materialRevision, materials: store.materials, cameraState: store.cameraState,
                        onMaterialError: {
                            guard store.rendererAttemptID == rendererAttempt else { return }
                            store.materialsFailed($0, revision: materialRevision)
                        },
                        onMaterialRendered: {
                            guard store.rendererAttemptID == rendererAttempt else { return }
                            store.materialsRendered(revision: materialRevision)
                        }
                    ) { message in
                        store.reportRendererError(message, attemptID: rendererAttempt)
                    }
                    .id(rendererAttempt)
                    .accessibilityLabel("3D mesh preview")
                } else {
                    ContentUnavailableView {
                        Label("Open a Dust3D model", systemImage: "cube.transparent")
                    } description: {
                        Text("Choose a .ds3 document to generate and inspect its mesh.")
                    } actions: {
                        Button("Open .ds3…") { isImporterPresented = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let revision = store.pendingOpenRevision {
                    VStack(spacing: 12) {
                        ProgressView("Generating mesh…")
                        Button("Cancel Opening") { store.cancelOpen(revision: revision) }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let requestID = store.pendingMaterialUpdateID {
                HStack {
                    ProgressView("Updating materials…")
                    Button("Cancel Material Update") { store.cancelMaterialUpdate(requestID: requestID) }
                }
                .controlSize(.small)
                .padding(8)
            }
            if let issue = store.materialIssue {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Showing geometry without materials")
                        Text(issue).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Retry Materials") { store.retryMaterials() }
                        .disabled(store.isLoading || store.isUpdatingMaterials)
                }
                .font(.caption).padding(12)
            }
            Divider()
            HStack {
                if let mesh = store.mesh {
                    Text("\(mesh.partCount) parts · \(mesh.nodeCount) nodes · \(mesh.triangleCount) triangles")
                        .monospacedDigit()
                    Spacer()
                    Text("Drag to orbit · Scroll to zoom")
                } else {
                    Text("Native SwiftUI viewer")
                    Spacer()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            if let warning = store.previewCompatibilityWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if let issue = store.materialSourceIssue {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Material source details unavailable", systemImage: "info.circle")
                    Text(issue).textSelection(.enabled)
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.bottom, 10)
                .accessibilityIdentifier("material-source-notice")
            }
        }
        .frame(minWidth: 650, minHeight: 450)
        .navigationTitle(store.documentName)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open a .ds3 document (⌘O)")
                Toggle(isOn: $isWireframe) { Label("Wireframe", systemImage: "square.3.layers.3d") }
                    .help("Show triangle edges")
                    .disabled(store.mesh == nil)
                Button {
                    store.cameraState.fit()
                } label: {
                    Label("Fit Model", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Reset the camera and fit the model")
                .disabled(store.mesh == nil)
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.dust3DDocument]) { result in
            switch result {
            case .success(let url): store.open(url)
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .onExitCommand(perform: cancelOperation)
        .onOpenURL { store.open($0) }
        .onDisappear { store.stop() }
        .focusedSceneValue(\.viewerRetryPreview, isImporterPresented ? nil : store.rendererRetryAction)
        .focusedSceneValue(\.viewerCancellation, cancelOperation)
        .focusedSceneValue(\.openDocument, { isImporterPresented = true })
    }
}

extension UTType {
    static let dust3DDocument = UTType(importedAs: "org.dust3d.document")
}
