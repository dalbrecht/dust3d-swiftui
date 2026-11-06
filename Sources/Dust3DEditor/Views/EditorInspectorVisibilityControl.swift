import SwiftUI

/// One editor window's toolbar visibility control.
struct EditorInspectorVisibilityControl: View {
    @Binding var isPresented: Bool

    var body: some View {
        Toggle(isOn: $isPresented) {
            Label("Inspector", systemImage: "sidebar.right")
        }
        .toggleStyle(.button)
        .accessibilityLabel("Inspector")
        .accessibilityIdentifier("editor.inspector.visibility")
        .help("Show or hide the inspector")
    }
}
