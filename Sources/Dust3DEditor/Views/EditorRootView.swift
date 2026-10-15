import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DRendering
import SwiftUI

struct EditorRootView: View {
    @Binding var file: EditorFileDocument
    @State private var store = EditorStore()
    @State private var isInspectorPresented = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Nodes").font(.headline)
                    Spacer()
                    Menu {
                        Button("Add Node") { store.addNode() }.disabled(!store.canAddNode)
                        Button("New Part") { store.addNode(newPart: true) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create node or part")
                    .disabled(store.isWorking || store.snapshot == nil)
                }.padding(12)
                Divider()
                List(selection: Binding(get: { store.snapshot?.selectedIDs ?? [] }, set: { store.select($0) })) {
                    ForEach(store.snapshot?.nodes ?? []) { node in
                        Label(node.title, systemImage: node.isEditable ? "circle.dotted" : "lock")
                            .tag(node.id)
                            .help(node.id)
                    }
                }
                .listStyle(.sidebar)
                .disabled(store.isWorking)
            }
            .frame(width: 180)
            Divider()
            VStack(spacing: 0) {
                if let error = store.errorMessage {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Dismiss") { store.errorMessage = nil }
                    }
                    .padding(10)
                    Divider()
                }
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Node canvas").font(.headline)
                            Spacer()
                            Picker("View", selection: $store.plane) {
                                ForEach(EditingPlane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .frame(width: 180)
                        }
                        .padding(12)
                        HStack {
                            Text("Locks").font(.caption).foregroundStyle(.secondary)
                            ForEach(EditingConstraint.allCases, id: \.self) { constraint in
                                Toggle(
                                    constraint.rawValue,
                                    isOn: Binding(
                                        get: { store.locks.contains(constraint) },
                                        set: { store.setLock(constraint, isLocked: $0) })
                                )
                                .toggleStyle(.button)
                                .accessibilityLabel("Lock \(constraint.rawValue)")
                                .accessibilityIdentifier("constraint-\(constraint.rawValue.lowercased())")
                            }
                        }
                        .controlSize(.small)
                        .disabled(store.isWorking || store.snapshot == nil)
                        .padding(.horizontal, 12).padding(.bottom, 8)
                        Divider()
                        NodeCanvas(store: store)
                    }
                    .frame(minWidth: 300)
                    Divider()
                    preview.frame(width: 320)
                }
                Divider()
                HStack {
                    Text("\(store.snapshot?.nodes.count ?? 0) nodes")
                    Spacer()
                    if store.isWorking {
                        ProgressView().controlSize(.small)
                        Text("Applying edit…")
                    } else {
                        Text("Drag empty canvas to select · Shift-drag to add · Drag nodes to move")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(10)
            }
            if isInspectorPresented {
                Divider()
                NodeInspector(store: store).frame(width: 250)
            }
        }
        .frame(minWidth: 1050, minHeight: 600)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    NSDocumentController.shared.openDocument(nil)
                } label: {
                    Label("Open", systemImage: "folder")
                }
                Button {
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                Divider()
                Button {
                    store.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }.disabled(!store.canUndo)
                Button {
                    store.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }.disabled(!store.canRedo)
                Button {
                    store.fit()
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                Toggle(isOn: $store.isWireframe) { Label("Wireframe", systemImage: "square.3.layers.3d") }
            }
        }
        .focusedSceneValue(\.editorStore, store)
        .task(id: file.identity) {
            store.onDocumentChanged = { file.data = $0 }
            await store.load(data: file.data)
        }
        .onDisappear { store.stop() }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mesh preview").font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            if let error = store.previewError {
                ContentUnavailableView {
                    Label("Preview unavailable", systemImage: "cube.transparent")
                } description: {
                    Text(error)
                }
            } else if let mesh = store.mesh {
                MeshViewport(
                    mesh: mesh, isWireframe: store.isWireframe, cameraReset: store.cameraReset,
                    meshRevision: store.previewRevision
                ) { store.previewError = $0 }
                .accessibilityLabel("3D mesh preview")
                Text("\(mesh.triangleCount) triangles · Drag to orbit · Scroll to zoom")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
                if store.isGenerating { ProgressView("Updating preview…").controlSize(.small).padding(8) }
                if !mesh.warning.isEmpty { Text(mesh.warning).font(.caption).padding(8) }
            } else if store.isGenerating {
                Spacer()
                ProgressView("Generating mesh…")
                Spacer()
            } else {
                ContentUnavailableView {
                    Label("Mesh preview", systemImage: "cube.transparent")
                } description: {
                    Text("Open a .ds3 model to begin editing.")
                }
            }
        }
    }
}
