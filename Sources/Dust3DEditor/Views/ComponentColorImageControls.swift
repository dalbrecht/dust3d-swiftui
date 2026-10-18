import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import UniformTypeIdentifiers

struct ComponentColorImageControls: View {
    let store: EditorStore
    let component: DocumentComponent
    @State private var isImporting = false
    @State private var importTarget: ComponentColorImageTarget?

    private var target: ComponentColorImageTarget? {
        store.snapshot.flatMap(ComponentColorImageTarget.init(snapshot:))
    }
    private var assets: [DocumentColorImageAsset] { store.snapshot?.colorImageAssets ?? [] }
    private var presentation: ComponentColorImagePresentation {
        .init(value: component.colorImage, assets: assets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color image").font(.headline)
            Text(presentation.source).font(.caption).textSelection(.enabled)
                // Recreate selectable AppKit text so its accessibility value follows the new source.
                .id(Array(presentation.source.utf8))
                .focusedValue(\.editorTextEditing, true)
            if let resource = presentation.resource {
                Text(resource).font(.caption).foregroundStyle(.secondary)
                    .id(Array(resource.utf8))
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
                                store.assignComponentColorImage(asset, target: target)
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
                store.clearComponentColorImage(target: target)
            } label: {
                Text("Clear Image Override").frame(maxWidth: .infinity, minHeight: 32)
            }
            .accessibilityLabel("Clear component color image override, keeping its asset")
            .accessibilityIdentifier("component-color-image-clear")
            .disabled(component.colorImage == .unset || target == nil)
            Text("Import, choose or clear is one undo step. Unused images stay in the file.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(store.isWorking)
        .onExitCommand { store.cancelColorImagePreparation() }
        .onChange(of: component.id) { _, _ in
            isImporting = false
            importTarget = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.png, .jpeg, .bmp, .gif, .tiff]) { result in
            defer { importTarget = nil }
            guard let importTarget else { return }
            switch result {
            case .success(let url): store.importComponentColorImage(url: url, target: importTarget)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { store.errorMessage = EditorStore.message(error) }
            }
        }
        .help(
            "PNG, JPEG, BMP, GIF or TIFF; first encoded frame. Maximum 32 MiB and 8192 pixels per side. Original PNG bytes are preserved."
        )
    }
}
