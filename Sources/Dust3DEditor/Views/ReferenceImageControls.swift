import Dust3DEditorModel
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ReferenceImageControls: View {
    let store: EditorStore
    @State private var isImporting = false
    @State private var composition: ReferenceCompositionPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu("Reference Image", systemImage: "photo") {
                    Button("Compose Reference Image…") {
                        guard let snapshot = store.snapshot else { return }
                        composition = ReferenceCompositionPresentation(snapshot: snapshot)
                    }
                    .disabled(store.isWorking || store.snapshot == nil)
                    Button("Import Reference Image…") { isImporting = true }
                        .disabled(store.isWorking || store.snapshot == nil)
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
        .sheet(item: $composition) { presentation in
            ReferenceCompositionSheet(store: store, target: presentation.target)
        }
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
    init(snapshot: EditorSnapshot) { target = ReferenceCompositionTarget(snapshot: snapshot) }
}
