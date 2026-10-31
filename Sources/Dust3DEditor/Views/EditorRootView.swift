import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import SwiftUI

private enum EditorInspectorSection: String, CaseIterable, Hashable {
    case selection = "Selection"
    case animations = "Animations"
}

struct EditorRootView: View {
    @Binding var file: EditorFileDocument
    let sourceURL: URL?
    @State private var store: EditorStore
    @State private var exportDestinations: EditorGeometryExportDestinationService
    @State private var exportWorkflow: EditorGeometryExportWorkflow
    @State private var isInspectorPresented = true
    @State private var inspectorSection = EditorInspectorSection.selection
    @State private var recoveryRegistrationID: UUID?

    init(file: Binding<EditorFileDocument>, sourceURL: URL? = nil) {
        let store = EditorStore(
            exportService: DocumentExportFileService(encoder: NativeGeometryExportEncoder()),
            animationCatalog: NativeAnimationCatalogLoader())
        let destinations = EditorGeometryExportDestinationService()
        _file = file
        self.sourceURL = sourceURL
        _store = State(initialValue: store)
        _exportDestinations = State(initialValue: destinations)
        _exportWorkflow = State(initialValue: EditorGeometryExportWorkflow(store: store, destinations: destinations))
    }

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
                ComponentSidebar(store: store)
                PartSidebar(store: store)
                EdgeSidebar(store: store)
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
                EditorGeometryExportStatusView(
                    phase: exportWorkflow.phase, format: exportWorkflow.format,
                    onCancel: exportWorkflow.cancel, onDismiss: exportWorkflow.dismissResult)
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
                        Toggle(
                            "Move Origin",
                            isOn: Binding(get: { store.isMovingOrigin }, set: { store.setMovingOrigin($0) })
                        )
                        .toggleStyle(.button)
                        .disabled(store.isWorking || store.snapshot?.origin == nil)
                        .help("Drag the origin marker; Escape cancels. Node picking resumes when this mode is off.")
                        .padding(.horizontal, 12).padding(.bottom, 8)
                        ReferenceImageControls(store: store)
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
                        Text(
                            store.isMovingOrigin
                                ? "Drag the origin marker · Escape cancels · Axis locks apply"
                                : "Drag empty canvas to select · Shift-drag to add · Drag nodes to move")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(10)
            }
            if isInspectorPresented {
                Divider()
                VStack(spacing: 0) {
                    Picker("Inspector section", selection: $inspectorSection) {
                        ForEach(EditorInspectorSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).padding(10)
                    Divider()
                    if inspectorSection == .animations {
                        AnimationPanel(store: store)
                    } else {
                        NodeInspector(store: store)
                    }
                }
                .frame(width: 250)
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
                }.disabled(!store.canSave)
                EditorGeometryExportMenu(canExport: exportWorkflow.canBegin) { format in
                    exportWorkflow.begin(format: format, sourceURL: sourceURL)
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
                Button {
                    isInspectorPresented = true
                    inspectorSection = .animations
                } label: {
                    Label("Animations", systemImage: "film")
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .accessibilityLabel("Show animations inspector")
                Toggle(isOn: $store.isWireframe) { Label("Wireframe", systemImage: "square.3.layers.3d") }
            }
        }
        .background(EditorExportWindowAnchor(service: exportDestinations).frame(width: 0, height: 0))
        .focusedSceneValue(\.editorStore, store)
        .focusedSceneValue(
            \.editorGeometryExportAction,
            EditorGeometryExportAction(
                canPerform: exportWorkflow.canBegin,
                perform: { format in exportWorkflow.begin(format: format, sourceURL: sourceURL) })
        )
        .onChange(of: sourceURL) { exportWorkflow.sourceDidChange() }
        .onChange(of: store.snapshot?.documentIdentity) { exportWorkflow.sourceDidChange() }
        .onChange(of: store.snapshot?.documentRevision) { exportWorkflow.sourceDidChange() }
        .task(id: file.identity) {
            if let recoveryRegistrationID { EditorRecoveryCopyRegistry.shared.unregister(recoveryRegistrationID) }
            let identifier = file.identity
            let recoveryStore = store
            recoveryRegistrationID = identifier
            EditorRecoveryCopyRegistry.shared.register(identifier) { [weak recoveryStore] in
                guard let recoveryStore else { throw EditorRecoveryCopyError.stopped }
                return try recoveryStore.recoverySnapshot(documentID: identifier)
            }
            store.onDocumentChanged = { file.data = $0 }
            store.onEditingChanged = { file.setEditing($0) }
            await store.load(data: file.data, fileIdentity: identifier)
        }
        .onExitCommand {
            EditorCommandScope.routeEscape(
                isMovingOrigin: store.isMovingOrigin, canCancelExport: exportWorkflow.canCancel,
                cancelOrigin: { store.cancelOriginDrag() }, cancelExport: { exportWorkflow.cancel() })
        }
        .onDisappear {
            if let recoveryRegistrationID { EditorRecoveryCopyRegistry.shared.unregister(recoveryRegistrationID) }
            recoveryRegistrationID = nil
            exportWorkflow.stop()
            store.stop()
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mesh preview").font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            if let error = store.renderError ?? (store.mesh == nil ? store.previewState.errorMessage : nil) {
                ContentUnavailableView {
                    Label("Preview unavailable", systemImage: "cube.transparent")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry Preview") { store.retryPreview() }.disabled(store.isGenerating)
                }
            } else if let mesh = store.mesh {
                let materialRevision = store.materialViewportRevision
                MeshViewport(
                    mesh: mesh, isWireframe: store.isWireframe, cameraReset: store.cameraReset,
                    meshRevision: store.materialViewportRevision, materials: store.materialContent,
                    onMaterialError: { store.materialsFailed($0, revision: materialRevision) },
                    onMaterialRendered: { store.materialsRendered(revision: materialRevision) }
                ) { store.renderError = $0 }
                .accessibilityLabel("3D mesh preview")
                if store.isUpdatingMaterials {
                    ProgressView("Updating materials…").controlSize(.small).padding(8)
                }
                if let issue = store.materialIssue {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Showing geometry without materials", systemImage: "exclamationmark.triangle")
                        Text(issue).textSelection(.enabled)
                        Button("Retry Materials") { store.retryMaterials() }
                            .disabled(store.isGenerating || store.isUpdatingMaterials || store.isWorking)
                    }
                    .font(.caption).padding(8)
                }
                if store.previewState.isStale {
                    Label("Showing last valid mesh", systemImage: "exclamationmark.triangle")
                        .font(.caption).padding(8)
                }
                if let error = store.previewState.errorMessage {
                    Text("Preview out of date: \(error)").font(.caption).padding(8)
                    Button("Retry Preview") { store.retryPreview() }.padding(.bottom, 8)
                }
                Text("\(mesh.triangleCount) triangles · Drag to orbit · Scroll to zoom")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
                if store.isGenerating { ProgressView("Updating preview…").controlSize(.small).padding(8) }
                if let warning = store.previewCompatibilityWarning { Text(warning).font(.caption).padding(8) }
            } else if store.isGenerating {
                Spacer()
                ProgressView("Generating mesh…")
                Spacer()
            } else {
                MeshPreviewPlaceholder(message: store.snapshot?.previewEmptyDescription)
            }
            if let issue = store.previewSourceIssue {
                Divider()
                PreviewDiagnosticNotice(kind: .source, message: issue.message)
            }
            if let issue = store.previewCacheStatistics?.cacheIssue {
                Divider()
                PreviewDiagnosticNotice(kind: .cache, message: issue.message)
            }
        }
    }
}
