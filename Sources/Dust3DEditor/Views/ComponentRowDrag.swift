import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import UniformTypeIdentifiers

struct ComponentRowDrag: ViewModifier {
    let store: EditorStore
    let id: String
    let isGroup: Bool
    fileprivate static let tokenType = UTType(exportedAs: "com.dalbrecht.dust3d.component-drag")

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onDrag {
                let provider = NSItemProvider()
                if let token = store.beginComponentDrag(grabbedID: id) {
                    let data = Data(token.uuidString.utf8)
                    provider.registerDataRepresentation(
                        forTypeIdentifier: Self.tokenType.identifier, visibility: .ownProcess
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                }
                return provider
            }
            .background {
                VStack(spacing: 0) {
                    dropZone(.before(id), alignment: .top)
                    if isGroup {
                        ComponentParentDropZone(store: store, parent: .component(id)) { Color.clear }
                    }
                    dropZone(.after(id), alignment: .bottom)
                }
                .accessibilityHidden(true)
            }
    }

    private func dropZone(_ placement: ComponentDropPlacement, alignment: Alignment) -> some View {
        ComponentDropZone(
            alignment: alignment,
            receive: { token in
                _ = store.dropComponents(token: token, at: placement)
            },
            content: { Color.clear }
        )
    }
}

struct ComponentParentDropZone<Content: View>: View {
    let store: EditorStore
    let parent: ComponentParent
    @ViewBuilder let content: () -> Content

    var body: some View {
        ComponentDropZone(
            alignment: nil,
            receive: { token in
                _ = store.dropComponents(token: token, in: parent)
            }, content: content)
    }
}

private struct ComponentDropZone<Content: View>: View {
    let alignment: Alignment?
    let receive: @MainActor @Sendable (UUID) -> Void
    @ViewBuilder let content: () -> Content
    @State private var targeted = false

    var body: some View {
        content()
            .overlay(alignment: alignment ?? .center) {
                if targeted {
                    if alignment != nil {
                        Rectangle().fill(Color.accentColor).frame(height: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [ComponentRowDrag.tokenType], isTargeted: $targeted, perform: loadToken)
    }

    private func loadToken(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else { return false }
        let receive = receive
        provider.loadDataRepresentation(forTypeIdentifier: ComponentRowDrag.tokenType.identifier) { data, _ in
            guard let data, data.count == 36, let token = UUID(uuidString: String(decoding: data, as: UTF8.self))
            else { return }
            Task { @MainActor in receive(token) }
        }
        return true
    }
}
