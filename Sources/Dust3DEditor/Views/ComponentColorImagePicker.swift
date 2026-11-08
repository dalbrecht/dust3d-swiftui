import SwiftUI
import UniformTypeIdentifiers

/// A file chooser completion belongs to the window request that presented it.
struct ComponentColorImagePicker: View {
    let store: EditorStore
    let requestID: UUID
    @State private var isPresented = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .fileImporter(
                isPresented: $isPresented, allowedContentTypes: [.png, .jpeg, .bmp, .gif, .tiff],
                allowsMultipleSelection: false
            ) { result in
                store.finishComponentColorImageChoice(requestID: requestID, result: result)
            } onCancellation: {
                store.cancelComponentColorImageChoice(requestID: requestID)
            }
            .onAppear { isPresented = true }
    }
}
