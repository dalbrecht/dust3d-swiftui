import Dust3DKit
import Dust3DRendering
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var store = ViewerStore()
    @State private var isImporterPresented = false
    @State private var isWireframe = false
    @State private var cameraReset = 0
    @State private var rendererError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let message = store.errorMessage ?? rendererError {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") {
                        store.errorMessage = nil
                        rendererError = nil
                    }
                }
                .padding()
                Divider()
            }
            ZStack {
                if let mesh = store.mesh {
                    MeshViewport(mesh: mesh, isWireframe: isWireframe, cameraReset: cameraReset) { message in
                        rendererError = message
                    }
                    .id(store.meshRevision)
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
                if store.isLoading {
                    ProgressView("Generating mesh…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Divider()
            HStack {
                if let mesh = store.mesh {
                    Text("\(mesh.partCount) parts · \(mesh.nodeCount) nodes · \(mesh.triangleCount) triangles")
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
            if let mesh = store.mesh, !mesh.warning.isEmpty {
                Text(mesh.warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
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
                    cameraReset += 1
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
        .onOpenURL { store.open($0) }
        .onChange(of: store.meshRevision) { rendererError = nil }
        .focusedSceneValue(\.openDocument, { isImporterPresented = true })
    }
}

extension UTType {
    static let dust3DDocument = UTType(importedAs: "org.dust3d.document")
}
