import SwiftUI

/// The drop owns a new native open request and never edits the receiving document.
struct EditorDocumentDropControl: View {
    @State private var isTargeted = false
    let isOpening: Bool
    let open: @MainActor (EditorDocumentDrop) -> Bool

    var body: some View {
        Label("Drop a .ds3 document to open", systemImage: "folder")
            .font(.caption)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                isTargeted && !isOpening ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, style: StrokeStyle(dash: [4, 3]))
            }
            .contentShape(Rectangle())
            .help("Open one local Dust3D document. The current document stays open.")
            .dropDestination(for: URL.self) { urls, _ in
                guard !isOpening, let drop = EditorDocumentDrop(urls: urls) else { return false }
                return open(drop)
            } isTargeted: {
                isTargeted = $0
            }
    }
}
