import SwiftUI

struct PartSidebar: View {
    let store: EditorStore

    var body: some View {
        let parts = store.snapshot?.parts ?? []
        if !parts.isEmpty {
            Divider()
            Text("Parts").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(parts) { part in
                        Button {
                            store.selectPart(part.id)
                        } label: {
                            Label(
                                part.title,
                                systemImage: part.isDisabled
                                    ? "nosign"
                                    : part.isLocked ? "lock" : part.isVisible ? "square.stack.3d.up" : "eye.slash"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.snapshot?.selectedPartID == part.id ? .accentColor : .secondary)
                        .accessibilityLabel("Select part \(part.title)")
                        .accessibilityValue(
                            [
                                store.snapshot?.selectedPartID == part.id ? "Selected" : "Not selected",
                                part.isVisible ? "Visible" : "Hidden", part.isLocked ? "Locked" : "Unlocked",
                                part.isDisabled ? "Disabled" : "Enabled",
                            ].joined(separator: ", ")
                        )
                        .help(part.id)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            .frame(maxHeight: 120)
            .disabled(store.isWorking)
        }
    }
}
