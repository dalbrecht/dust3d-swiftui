import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import UniformTypeIdentifiers

struct ComponentColorImageControls: View {
    let store: EditorStore
    let component: DocumentComponent?
    let graphTarget: ComponentMeshSelectionTarget?
    @State private var isImporting = false
    @State private var importTarget: EditorStore.ComponentColorImageDestination?

    init(store: EditorStore, component: DocumentComponent) {
        self.store = store
        self.component = component
        graphTarget = nil
    }

    init(store: EditorStore, graphTarget: ComponentMeshSelectionTarget) {
        self.store = store
        component = nil
        self.graphTarget = graphTarget
    }

    private var target: EditorStore.ComponentColorImageDestination? {
        let destination: EditorStore.ComponentColorImageDestination?
        if let graphTarget {
            destination = .graph(graphTarget)
        } else {
            destination = store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:)).map { .component($0) }
        }
        guard let destination, store.canEditComponentColorImage(destination) else { return nil }
        return destination
    }

    private var hasOverride: Bool {
        if let component { return component.colorImage != .unset }
        guard let graphTarget, let snapshot = store.snapshot else { return false }
        return graphTarget.graphColorImageComponents(in: snapshot).contains { $0.colorImage != .unset }
    }
    private var assets: [DocumentColorImageAsset] { store.snapshot?.colorImageAssets ?? [] }
    private var presentation: ComponentColorImagePresentation? {
        component.map { .init(value: $0.colorImage, assets: assets) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color image").font(.headline)
            if let presentation {
                Text(presentation.source).font(.caption).textSelection(.enabled)
                    // Recreate selectable AppKit text so its accessibility value follows the new source.
                    .id(Array(presentation.source.utf8))
                    .focusedValue(\.editorTextEditing, true)
                if let resource = presentation.resource {
                    Text(resource).font(.caption).foregroundStyle(.secondary)
                        .id(Array(resource.utf8))
                }
            } else {
                Text("One image applies to every owning Model component.").font(.caption)
            }
            Button {
                importTarget = target
                isImporting = importTarget != nil
            } label: {
                Label("Import Image…", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .accessibilityLabel("Import component color image")
            .accessibilityIdentifier("component-color-image-import")
            .disabled(target == nil)
            if store.isPreparingColorImage {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing image…").font(.caption)
                    Spacer(minLength: 4)
                    Button("Cancel") { store.cancelColorImagePreparation() }
                        .accessibilityLabel("Cancel component image preparation")
                }
            }
            if assets.isEmpty {
                Text("No retained images.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Retained images · \(assets.count)").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(assets) { asset in
                            Button {
                                guard let target else { return }
                                store.assignComponentColorImage(asset, destination: target)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ComponentColorImagePresentation.summary(asset.assetName))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Text(
                                        asset.issue.map {
                                            ComponentColorImagePresentation.summary($0.localizedDescription)
                                        }
                                            ?? "\(asset.encodedByteCount) bytes · Choose to use"
                                    )
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            }
                            .disabled(!asset.canAssign || target == nil)
                            .accessibilityLabel(
                                "Use retained image \(ComponentColorImagePresentation.summary(asset.assetName))")
                        }
                    }
                    .padding(2)
                }
                .frame(height: min(180, CGFloat(assets.count) * 72))
                .accessibilityLabel("Retained component images")
            }
            Button {
                guard let target else { return }
                store.clearComponentColorImage(destination: target)
            } label: {
                Text("Clear Image Override").frame(maxWidth: .infinity, minHeight: 32)
            }
            .accessibilityLabel("Clear component color image override, keeping its asset")
            .accessibilityIdentifier("component-color-image-clear")
            .disabled(!hasOverride || target == nil)
            Text("Import, choose or clear is one undo step. Unused images stay in the file.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(store.isWorking)
        .onExitCommand { store.cancelColorImagePreparation() }
        .onChange(of: component?.id) { _, _ in
            isImporting = false
            importTarget = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.png, .jpeg, .bmp, .gif, .tiff]) { result in
            defer { importTarget = nil }
            guard let importTarget, store.canEditComponentColorImage(importTarget) else { return }
            switch result {
            case .success(let url): store.importComponentColorImage(url: url, destination: importTarget)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { store.errorMessage = EditorStore.message(error) }
            }
        }
        .help(
            "PNG, JPEG, BMP, GIF or TIFF; first encoded frame. Maximum 32 MiB and 8192 pixels per side. Original PNG bytes are preserved."
        )
    }
}
