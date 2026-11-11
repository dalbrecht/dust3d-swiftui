import Dust3DEditorModel
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ReferenceImageControls: View {
    let store: EditorStore
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @Binding var composition: ReferenceCompositionPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu("Reference Image", systemImage: "photo") {
                    Button("Compose Reference Image…") {
                        guard composition == nil, let target = store.referenceCompositionTarget else { return }
                        composition = ReferenceCompositionPresentation(target: target)
                    }
                    .disabled(store.referenceCompositionTarget == nil)
                    Button("Import Reference Image…") { isImporting = true }
                        .disabled(store.isWorking || store.snapshot == nil)
                    Button("Clear Reference Artwork") { store.clearReferenceArtwork() }
                        .disabled(!store.canClearReferenceArtwork)
                        .help("Clear the image while keeping its dimensions and canvas alignment. You can undo this.")
                    Button("Remove Reference Image", role: .destructive) { store.removeReferenceImage() }
                        .disabled(store.isWorking || !store.hasReferenceImage)
                }
                Spacer()
                Toggle(
                    "Show",
                    isOn: Binding(
                        get: { store.showsReferenceImage },
                        set: {
                            store.showsReferenceImage = $0
                            store.fit()
                        })
                )
                .accessibilityLabel("Show reference image")
                .disabled(!store.hasReferenceImage)
            }
            Label("Drop Front or Front + Side images", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    isDropTargeted ? Color.accentColor.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, style: StrokeStyle(dash: [4, 3]))
                }
                .contentShape(Rectangle())
                .help(
                    "Drop one or two local images to compose a reference image. The first is Front and the second is Side."
                )
                .dropDestination(for: URL.self) { urls, _ in
                    guard composition == nil, let target = store.referenceCompositionTarget,
                        let drop = ReferenceCompositionDrop(urls: urls)
                    else { return false }
                    composition = ReferenceCompositionPresentation(target: target, droppedSources: drop)
                    return true
                } isTargeted: {
                    isDropTargeted = $0
                }
            if store.hasReferenceImage {
                HStack {
                    Text("Opacity")
                    Slider(
                        value: Binding(get: { store.referenceImageOpacity }, set: { store.referenceImageOpacity = $0 }),
                        in: 0...1
                    )
                    .accessibilityLabel("Reference image opacity")
                }
            }
            if store.hasReferenceImage && store.isLoadingReferenceImage {
                ProgressView("Loading reference image…").controlSize(.small)
            }
            if let error = store.referenceImageError {
                Label(error, systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .help(
            "PNG, JPEG, BMP, GIF or TIFF. Uses the first frame. Maximum 32 MiB, 8192 pixels per side and 16 megapixels. Display settings stay in this window."
        )
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.png, .jpeg, .bmp, .gif, .tiff]) { result in
            switch result {
            case .success(let url): store.importReferenceImage(from: url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { store.errorMessage = EditorStore.message(error) }
            }
        }
    }
}

/// Target and visibility share one value so first presentation cannot render before its target exists.
struct ReferenceCompositionPresentation: Identifiable {
    let id = UUID()
    let target: ReferenceCompositionTarget
    let droppedSources: ReferenceCompositionDrop?

    init(target: ReferenceCompositionTarget, droppedSources: ReferenceCompositionDrop? = nil) {
        self.target = target
        self.droppedSources = droppedSources
    }
}
