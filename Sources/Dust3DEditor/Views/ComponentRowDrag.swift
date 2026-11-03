import Dust3DDocument
import SwiftUI
import UniformTypeIdentifiers

struct ComponentRowDrag: ViewModifier {
    let store: EditorStore
    let id: String
    private static let tokenType = UTType(exportedAs: "com.dalbrecht.dust3d.component-drag")

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
                    dropZone(.after(id), alignment: .bottom)
                }
                .accessibilityHidden(true)
            }
    }

    private func dropZone(_ placement: ComponentDropPlacement, alignment: Alignment) -> some View {
        ComponentInsertionZone(alignment: alignment, type: Self.tokenType) { providers in
            guard providers.count == 1, let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: Self.tokenType.identifier) { data, _ in
                guard let data, data.count == 36, let token = UUID(uuidString: String(decoding: data, as: UTF8.self))
                else { return }
                Task { @MainActor in
                    _ = store.dropComponents(token: token, at: placement)
                }
            }
            return true
        }
    }
}

private struct ComponentInsertionZone: View {
    let alignment: Alignment
    let type: UTType
    let receive: ([NSItemProvider]) -> Bool
    @State private var targeted = false

    var body: some View {
        Rectangle().fill(.clear)
            .overlay(alignment: alignment) {
                if targeted {
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [type], isTargeted: $targeted, perform: receive)
    }
}
