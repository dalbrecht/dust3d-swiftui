import Dust3DEditorModel
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ReferenceImageControls: View {
    let store: EditorStore
    let fileIdentity: UUID
    let currentFileIdentity: @MainActor () -> UUID
    @State private var isDropTargeted = false
    @Binding var composition: ReferenceCompositionPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu("Reference Image", systemImage: "photo") {
                    let remove = store.referenceImageRemovalAction(
                        fileIdentity: fileIdentity, currentFileIdentity: { currentFileIdentity() })
                    Button("Compose Reference Image…") {
                        guard composition == nil, let target = store.referenceCompositionTarget else { return }
                        composition = ReferenceCompositionPresentation(target: target)
                    }
                    .disabled(store.referenceCompositionTarget == nil)
                    Button("Import Reference Image…") {
                        guard currentFileIdentity() == fileIdentity else { return }
                        store.chooseReferenceImage(fileIdentity: fileIdentity)
                    }
                    .disabled(!store.canChooseReferenceImage(fileIdentity: fileIdentity))
                    Button("Remove Reference Image", role: .destructive) { remove?() }
                        .disabled(remove == nil)
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
        .background {
            if let requestID = store.referenceImageFileRequestID {
                ReferenceImageFilePicker(
                    store: store, requestID: requestID, currentFileIdentity: { currentFileIdentity() }
                )
                .id(requestID)
            }
        }
    }
}

private struct ReferenceImageFilePicker: View {
    let store: EditorStore
    let requestID: UUID
    let currentFileIdentity: @MainActor () -> UUID
    @State private var isPresented = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .fileImporter(
                isPresented: $isPresented, allowedContentTypes: [.png, .jpeg, .bmp, .gif, .tiff],
                allowsMultipleSelection: false
            ) { result in
                store.finishReferenceImageChoice(
                    requestID: requestID, result: result, currentFileIdentity: { currentFileIdentity() })
            } onCancellation: {
                store.cancelReferenceImageChoice(requestID: requestID)
            }
            .onAppear { isPresented = true }
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
