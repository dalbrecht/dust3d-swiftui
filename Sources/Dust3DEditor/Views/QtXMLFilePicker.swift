import SwiftUI
import UniformTypeIdentifiers

/// A picker stays attached to its original window and request until completion or cancellation.
struct QtXMLFilePicker: View {
    let store: EditorStore
    let requestID: UUID
    @State private var isPresented = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .fileImporter(
                isPresented: $isPresented, allowedContentTypes: [.xml], allowsMultipleSelection: false
            ) { result in
                store.finishQtXMLFileChoice(requestID: requestID, result: result)
            } onCancellation: {
                store.cancelQtXMLFileChoice(requestID: requestID)
            }
            .onAppear { isPresented = true }
    }
}
